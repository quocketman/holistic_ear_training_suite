import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/enums.dart';
import '../models/musical_state.dart';
import '../models/tone_token_colors.dart';
import '../services/audio_service.dart';
import '../services/pdf_export.dart';
import '../services/signup_service.dart';
import '../services/url_state.dart';
import '../utils/solfege_parser.dart';
import '../widgets/solfege_highlight_controller.dart';
import '../widgets/whiteboard_canvas.dart';

class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({super.key});

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  // Persistent state across page navigation.
  static String _persistedSolfege = '';
  static String _persistedTitle = '';
  static CanvasJustify _persistedJustify = CanvasJustify.left;
  // Session-scoped — resets on page reload. Suppresses the welcome modal
  // after the user has dismissed it once in this browser tab.
  static bool _welcomeShown = false;

  late final SolfegeHighlightController _controller;
  late final TextEditingController _titleController;
  final _canvasKey = GlobalKey();
  final AudioService _audioService = AudioService();
  final Map<int, NoteHandle> _activeNotes = {};
  // Controls the horizontal scroll position of the canvas viewport. After
  // each input change we jump to maxScrollExtent so the most recently typed
  // tokens are always visible at the right edge.
  final _canvasScrollController = ScrollController();
  // Toggled by the AppBar ? icon. The help panel slides in below the input
  // area as an overlay on the canvas, so users can read the directions while
  // typing.
  bool _isHelpVisible = false;
  // Bottom signup banner — persistent across the app.
  final _signupEmailController = TextEditingController();
  final _signupEmailFocus = FocusNode();
  bool _isSubmittingSignup = false;
  String? _signupFeedback;
  bool _signupFeedbackIsError = false;
  Timer? _signupFeedbackTimer;

  SolfegeParseResult _parsed = const SolfegeParseResult(
    notes: [],
    unrecognized: [],
  );
  CanvasJustify _justify = CanvasJustify.left;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    // If the page URL carries an encoded solfège payload (set by a PDF's
    // "Edit in Whiteboard" link or a share URL), it overrides the
    // in-memory persisted text. URL > previous session.
    final fromUrl = readSolfegeTextFromUrl();
    final initialText =
        (fromUrl != null && fromUrl.isNotEmpty) ? fromUrl : _persistedSolfege;
    _controller = SolfegeHighlightController(text: initialText);
    _titleController = TextEditingController(text: _persistedTitle);
    _justify = _persistedJustify;
    if (initialText.isNotEmpty) {
      _parsed = SolfegeParser.parse(initialText);
    }
    // Show the welcome modal once per browser tab — first paint after build.
    if (!_welcomeShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _welcomeShown = true;
        showDialog<void>(
          context: context,
          builder: (_) => const _WelcomeModal(),
        );
      });
    }
  }

  @override
  void dispose() {
    // Save state for next visit before tearing down controllers.
    _persistedSolfege = _controller.text;
    _persistedTitle = _titleController.text;
    _persistedJustify = _justify;
    for (final h in _activeNotes.values) {
      h.release();
    }
    _activeNotes.clear();
    _audioService.dispose();
    _controller.dispose();
    _titleController.dispose();
    _canvasScrollController.dispose();
    _signupEmailController.dispose();
    _signupEmailFocus.dispose();
    _signupFeedbackTimer?.cancel();
    super.dispose();
  }

  int _midiForNote(SolfegeNote note, int tonic) =>
      tonic + note.chromaticOffset + note.octave * 12;

  Future<void> _onNoteDown(int index) async {
    if (index < 0 || index >= _parsed.notes.length) return;
    final note = _parsed.notes[index];
    if (note.isSpacer) return;
    final tonic = context.read<MusicalState>().currentTonic;
    final midi = _midiForNote(note, tonic);
    if (midi < 0 || midi > 127) return;
    final handle = await _audioService.noteOn(
      midi,
      params: AudioService.globalSynthParams,
    );
    if (handle != null) {
      _activeNotes[index]?.release();
      _activeNotes[index] = handle;
    }
  }

  void _onNoteUp(int index) {
    final handle = _activeNotes.remove(index);
    handle?.release();
  }

  void _onInputChanged(String value) {
    setState(() {
      _parsed = SolfegeParser.parse(value);
    });
    // After the canvas relayouts with the new content, jump the viewport to
    // the right edge so the user always sees what they just typed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canvasScrollController.hasClients) return;
      final position = _canvasScrollController.position;
      _canvasScrollController.jumpTo(position.maxScrollExtent);
    });
  }

  /// True only on iOS / Android. Desktop and web are always horizontal.
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  CanvasLayout _resolvedLayout(BuildContext context) {
    if (_isMobile) {
      // Mobile follows device orientation.
      return MediaQuery.of(context).orientation == Orientation.portrait
          ? CanvasLayout.vertical
          : CanvasLayout.horizontal;
    }
    // Desktop and web: always horizontal.
    return CanvasLayout.horizontal;
  }

  Future<void> _downloadPdf() async {
    if (_parsed.notes.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final title = _titleController.text.trim();
      final prefix = title.isNotEmpty
          ? title
              .replaceAll(RegExp(r'[^\w\s-]'), '')
              .replaceAll(RegExp(r'\s+'), '_')
          : 'whiteboard';
      final destination = await exportRepaintBoundaryToPdf(
        boundaryKey: _canvasKey,
        filenamePrefix: prefix,
        title: title,
        solfegeText: _controller.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $destination')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (!msg.contains('Save cancelled')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── KEY + OCTAVE pickers (live in the AppBar leading row) ─────────────

  /// Pitch-class picker — replaces the old in-body `KeyOctaveControls` key
  /// dropdown. PopupMenu shows the 12 pitch classes; tapping one sets the
  /// tonic while preserving the current octave.
  Widget _buildKeyPicker() {
    const octaveOffset = 4; // MIDI 48 = middle "do" octave 0
    return Consumer<MusicalState>(
      builder: (context, state, _) {
        final current = state.currentTonicPitchClass;
        return PopupMenuButton<PitchClass>(
          tooltip: 'Key — do = ${current.displayName}',
          icon: const Icon(Icons.vpn_key_outlined),
          onSelected: (pc) {
            final octave = (state.currentTonic ~/ 12) - octaveOffset;
            state.currentTonic =
                (pc.value + (octave + octaveOffset) * 12).clamp(0, 127);
          },
          itemBuilder: (_) => PitchClass.values
              .map((p) => PopupMenuItem(
                    value: p,
                    child: Text(
                      'do = ${p.displayName}',
                      style: TextStyle(
                        fontWeight: p == current
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  /// Octave picker — replaces the old in-body octave +/- stepper. PopupMenu
  /// shows offsets −2 through +2 from the middle-do octave.
  Widget _buildOctavePicker() {
    const octaveOffset = 4;
    return Consumer<MusicalState>(
      builder: (context, state, _) {
        final pc = state.currentTonicPitchClass;
        final current = (state.currentTonic ~/ 12) - octaveOffset;
        return PopupMenuButton<int>(
          tooltip: 'Octave (currently $current)',
          onSelected: (oct) {
            state.currentTonic =
                (pc.value + (oct + octaveOffset) * 12).clamp(0, 127);
          },
          itemBuilder: (_) => [-2, -1, 0, 1, 2]
              .map((o) => PopupMenuItem(
                    value: o,
                    child: Text(
                      'Octave $o',
                      style: TextStyle(
                        fontWeight:
                            o == current ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ))
              .toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              '8ve',
              style: GoogleFonts.sourceSans3(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── AppBar action handlers ─────────────────────────────────────────────

  Future<void> _openTuneIndigo() async {
    await launchUrl(Uri.parse('https://tuneindigo.com'));
  }

  Future<void> _openVideo() async {
    // Tune Indigo Music YouTube channel — once a specific intro video is
    // recorded, swap in its watch URL.
    await launchUrl(Uri.parse('https://www.youtube.com/@tuneindigomusic'));
  }

  void _onShare() {
    // Stub — full share UX (URL state encoding + social) is the next
    // feature after wrap-up.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share coming soon')),
    );
  }

  // Step-through justify: one icon, cycles left → center → right → left.
  IconData get _justifyIcon {
    switch (_justify) {
      case CanvasJustify.left:
        return Icons.format_align_left;
      case CanvasJustify.center:
        return Icons.format_align_center;
      case CanvasJustify.right:
        return Icons.format_align_right;
    }
  }

  String get _justifyLabel {
    switch (_justify) {
      case CanvasJustify.left:
        return 'left';
      case CanvasJustify.center:
        return 'center';
      case CanvasJustify.right:
        return 'right';
    }
  }

  void _cycleJustify() {
    setState(() {
      switch (_justify) {
        case CanvasJustify.left:
          _justify = CanvasJustify.center;
        case CanvasJustify.center:
          _justify = CanvasJustify.right;
        case CanvasJustify.right:
          _justify = CanvasJustify.left;
      }
    });
  }

  void _onShowHelp() {
    setState(() => _isHelpVisible = !_isHelpVisible);
  }

  void _hideHelp() {
    if (_isHelpVisible) setState(() => _isHelpVisible = false);
  }

  void _onSignup() {
    // AppBar ✉ icon opens the centered signup modal — a more deliberate
    // signup affordance than just focusing the persistent bottom banner.
    showDialog<void>(
      context: context,
      builder: (_) => const _SignupModal(),
    );
  }

  Future<void> _onSubmitSignup() async {
    if (_isSubmittingSignup) return;
    final email = _signupEmailController.text.trim();
    if (email.isEmpty) return;

    // Visible failure until the Worker URL is pasted into SignupService.
    if (!SignupService.endpointConfigured) {
      _showSignupFeedback(
        "Form not yet wired — Worker URL still says REPLACE-ME",
        isError: true,
      );
      return;
    }

    setState(() {
      _isSubmittingSignup = true;
      _signupFeedback = null;
    });

    final result = await SignupService.subscribe(email);

    if (!mounted) return;
    setState(() => _isSubmittingSignup = false);

    if (result.success) {
      _signupEmailController.clear();
      _signupEmailFocus.unfocus();
      _showSignupFeedback(
        result.alreadySubscribed
            ? "You're already on the list — thanks!"
            : "You're on the list. Welcome!",
        isError: false,
      );
    } else {
      _showSignupFeedback(
        result.errorMessage ?? 'Something went wrong.',
        isError: true,
      );
    }
  }

  void _showSignupFeedback(String message, {required bool isError}) {
    setState(() {
      _signupFeedback = message;
      _signupFeedbackIsError = isError;
    });
    _signupFeedbackTimer?.cancel();
    _signupFeedbackTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _signupFeedback = null);
    });
  }

  // ── Persistent signup banner ──────────────────────────────────────────

  Widget _buildSignupBanner() {
    // "so" (Blue, #3F55C7) — chromatic offset 7. Matches the AppBar so the
    // app's chrome reads as a single top + bottom frame.
    final chromeColor = ToneTokenColors.getColor(7);
    final headline = _signupFeedback ?? 'Weekly lessons in your inbox';
    final headlineColor = _signupFeedback != null && _signupFeedbackIsError
        ? Colors.amber.shade100
        : Colors.white;

    return Material(
      color: chromeColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: GoogleFonts.sourceSans3(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: headlineColor,
                ),
                child: Text(headline),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: TextField(
                  controller: _signupEmailController,
                  focusNode: _signupEmailFocus,
                  enabled: !_isSubmittingSignup,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _onSubmitSignup(),
                  style: GoogleFonts.sourceSans3(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'your@email.com',
                    hintStyle: GoogleFonts.sourceSans3(
                      fontSize: 15,
                      color: Colors.black45,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isSubmittingSignup ? null : _onSubmitSignup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: chromeColor,
                  disabledBackgroundColor: Colors.white70,
                  disabledForegroundColor: chromeColor.withValues(alpha: 0.6),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: _isSubmittingSignup
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: chromeColor,
                        ),
                      )
                    : Text(
                        'Subscribe',
                        style: GoogleFonts.sourceSans3(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Help drawer ───────────────────────────────────────────────────────

  Widget _buildHelpPanel() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How to use Whiteboard',
                    style: GoogleFonts.sourceSans3(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Improve your ear by connecting lyrics to solfège.',
                    style: GoogleFonts.sourceSans3(
                      fontSize: 17,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Close',
              onPressed: _hideHelp,
            ),
          ],
        ),
        const SizedBox(height: 16),
            const _HelpItem(
              text: 'Type a lyric syllable, forward slash, solfège.',
              example: 'rain/so',
            ),
            const _HelpItem(
              text: 'Type lyrics alone.',
              sub:
                  "Ensure a lyric syllable isn't treated like solfège: follow it with a forward slash.",
              example: 're/',
            ),
            const _HelpItem(
              text: 'Type solfège alone.',
              sub:
                  "Ensure a solfège syllable isn't treated like a lyric: precede it with a forward slash.",
              example: '/re',
            ),
            const _HelpItem(
              text: 'Higher octave solfège',
              suffix: 'single quote',
              example: "do'",
            ),
            const _HelpItem(
              text: 'Lower octave solfège',
              suffix: 'comma',
              example: 'do,',
            ),
            const _HelpItem(
              text: 'Add a little space',
              suffix: 'underscore',
              example: '_',
            ),
            const _HelpItem(
              text: 'Group tones',
              sub:
                  'Place | at the beginning and ending of the group.',
              example: '| do mi so |',
            ),
      ],
    );
  }

  void _clear() {
    _controller.clear();
    _titleController.clear();
    _persistedSolfege = '';
    _persistedTitle = '';
    setState(() {
      _parsed = const SolfegeParseResult(notes: [], unrecognized: []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = _resolvedLayout(context);
    final canvasSize = layout.exportSize;

    // "so" (Blue, #3F55C7) — chromatic offset 7. AppBar uses this; the
    // bottom signup banner mirrors it so chrome reads as one cohesive frame.
    final chromeColor = ToneTokenColors.getColor(7);
    return Scaffold(
      bottomNavigationBar: _buildSignupBanner(),
      appBar: AppBar(
        backgroundColor: chromeColor,
        foregroundColor: Colors.white,
        title: const Text('Tune Indigo Whiteboard'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: 220,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bulb logo links to tuneindigo.com.
            InkWell(
              onTap: _openTuneIndigo,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: SvgPicture.asset(
                  'assets/branding/brand_bulb_tipped.svg',
                  width: 26,
                  height: 26,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            _buildKeyPicker(),
            _buildOctavePicker(),
            // PLAY — greyed out for now. Real keyboard-arrow step-through
            // playback lands as the next feature.
            const IconButton(
              icon: Icon(Icons.play_arrow_outlined),
              tooltip: 'Play (coming soon)',
              onPressed: null,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_download_outlined),
            tooltip: 'Download PDF',
            onPressed: _parsed.notes.isEmpty || _exporting ? null : _downloadPdf,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: _onShare,
          ),
          const IconButton(
            icon: Icon(Icons.save_outlined),
            tooltip: 'Save (coming soon)',
            onPressed: null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear',
            onPressed: _parsed.notes.isEmpty && _titleController.text.isEmpty
                ? null
                : _clear,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How to use',
            onPressed: _onShowHelp,
          ),
          IconButton(
            icon: const Icon(Icons.smart_display_outlined),
            tooltip: 'Watch intro',
            onPressed: _openVideo,
          ),
          IconButton(
            icon: const Icon(Icons.email_outlined),
            tooltip: 'Subscribe to updates',
            onPressed: _onSignup,
          ),
          IconButton(
            icon: Icon(_justifyIcon),
            tooltip: 'Align ($_justifyLabel)',
            onPressed: _cycleJustify,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Column(
            children: [
              Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Title',
                    hintText: 'e.g. Mary Had a Little Lamb',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  onChanged: _onInputChanged,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Lyrics & solfège',
                    hintText: "e.g. Twink-/do le/do twink-/so le/so lit-/la tle/la star/so",
                  ),
                  // Multi-line ergonomics: starts 3 lines tall, grows as the
                  // user types more lines. Newlines are treated as whitespace
                  // by the parser — they're for input organisation only.
                  minLines: 3,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                ),
                if (_parsed.unrecognized.isNotEmpty || _statusLine().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _statusLine(),
                      style: TextStyle(
                        fontSize: 12,
                        color: _parsed.unrecognized.isNotEmpty
                            ? Colors.redAccent
                            : Colors.grey[500],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Live preview — fills available space.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const helpPanelWidth = 360.0;
                return Stack(
                  children: [
                    // Live preview — fills available space.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _canvasScrollController,
                      child: WhiteboardCanvas(
                        notes: _parsed.notes,
                        layout: layout,
                        tokenSize: 50.0,
                        fitToSize: Size(
                          constraints.maxWidth - 24,
                          constraints.maxHeight - 24,
                        ),
                        title: _titleController.text.trim(),
                        justify: _justify,
                        onNoteDown: _onNoteDown,
                        onNoteUp: _onNoteUp,
                      ),
                    ),
                    // Help panel — slides in from the right edge of the
                    // canvas, leaving the left side (where solfège
                    // typically lives, especially before auto-scroll
                    // kicks in) unobstructed.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      right: _isHelpVisible ? 0 : -helpPanelWidth,
                      top: 0,
                      bottom: 0,
                      width: helpPanelWidth,
                      child: Material(
                        color: ToneTokenColors.getColor(7), // so blue
                        elevation: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: _buildHelpPanel(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
            ],
          ),
          // Full-res canvas for PNG export — positioned off-screen so it
          // lays out at full intrinsic size and gets fully painted, but is
          // never visible. Stack's clipBehavior hides the overflow.
          Positioned(
            left: -canvasSize.width - 100,
            top: -canvasSize.height - 100,
            width: canvasSize.width,
            height: canvasSize.height,
            child: RepaintBoundary(
              key: _canvasKey,
              child: WhiteboardCanvas(
                notes: _parsed.notes,
                layout: layout,
                title: _titleController.text.trim(),
                justify: _justify,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLine() {
    if (_controller.text.trim().isEmpty) {
      return 'Type syllables separated by spaces.';
    }
    final parts = <String>[];
    parts.add('${_parsed.notes.length} note${_parsed.notes.length == 1 ? '' : 's'}');
    if (_parsed.unrecognized.isNotEmpty) {
      parts.add('unrecognized: ${_parsed.unrecognized.join(', ')}');
    }
    return parts.join(' • ');
  }
}

/// One row of help text in the directions drawer. Shows a bullet, the main
/// instruction, an optional subtext explanation, an optional "(suffix)"
/// inline aside, and a styled example code chip.
class _HelpItem extends StatelessWidget {
  final String text;
  final String? sub;
  final String? suffix;
  final String example;

  const _HelpItem({
    required this.text,
    this.example = '',
    this.sub,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.sourceSans3(
      fontSize: 17,
      color: Colors.white,
      height: 1.35,
    );
    final subStyle = GoogleFonts.sourceSans3(
      fontSize: 15,
      color: Colors.white.withValues(alpha: 0.78),
      height: 1.35,
    );
    final suffixStyle = GoogleFonts.sourceSans3(
      fontSize: 17,
      color: Colors.white.withValues(alpha: 0.78),
      height: 1.35,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Colors.white54,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: textStyle,
                    children: [
                      TextSpan(text: text),
                      if (suffix != null) ...[
                        TextSpan(
                          text: '  →  $suffix',
                          style: suffixStyle,
                        ),
                      ],
                    ],
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 4),
                  Text(sub!, style: subStyle),
                ],
                if (example.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      example,
                      style: GoogleFonts.sourceCodePro(
                        fontSize: 15,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered signup modal triggered by the AppBar ✉ icon. Has its own state
/// so the parent screen doesn't carry modal-specific submission state.
class _SignupModal extends StatefulWidget {
  const _SignupModal();

  @override
  State<_SignupModal> createState() => _SignupModalState();
}

class _SignupModalState extends State<_SignupModal> {
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _feedback = null;
    });

    final result = await SignupService.subscribe(email);
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      _feedback = result.success
          ? (result.alreadySubscribed
              ? "You're already on the list — thanks!"
              : "You're on the list. Welcome!")
          : (result.errorMessage ?? 'Something went wrong.');
      _feedbackIsError = !result.success;
    });

    // On success, give the user a beat to read the confirmation and auto-close.
    if (result.success) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final soBlue = ToneTokenColors.getColor(7);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.fromLTRB(28, 20, 20, 28),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Stay connected with Tune Indigo',
                      style: GoogleFonts.sourceSans3(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Weekly ear-training lessons, new tools, and tips delivered to your inbox.',
              style: GoogleFonts.sourceSans3(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _emailController,
              autofocus: true,
              enabled: !_isSubmitting,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.sourceSans3(
                fontSize: 16,
                color: Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'your@email.com',
                hintStyle: GoogleFonts.sourceSans3(
                  fontSize: 16,
                  color: Colors.black45,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              Text(
                _feedback!,
                style: GoogleFonts.sourceSans3(
                  fontSize: 14,
                  color: _feedbackIsError
                      ? Colors.amber.shade300
                      : Colors.lightGreenAccent.shade100,
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: soBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: soBlue.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Subscribe',
                        style: GoogleFonts.sourceSans3(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// First-load welcome modal. Centered, so-blue card with the Tune Indigo
/// brand bulb at the top, a headline matched to the AppBar title size, and
/// body text styled like the help drawer's item-level text.
///
/// Auto-shown once per browser tab via [_WhiteboardScreenState._welcomeShown].
/// The temp body copy will be revised by Hans tomorrow.
class _WelcomeModal extends StatelessWidget {
  const _WelcomeModal();

  @override
  Widget build(BuildContext context) {
    final soBlue = ToneTokenColors.getColor(7);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Stack(
          children: [
            // Card body.
            Container(
              decoration: BoxDecoration(
                color: soBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.fromLTRB(36, 36, 36, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/branding/brand_bulb_tipped.svg',
                    width: 72,
                    height: 72,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Headline — matches the AppBar title size visually.
                  Text(
                    'Welcome',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sourceSans3(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Body — styled like the help drawer's item text.
                  Text(
                    'One of the best ways to improve your ear and musical '
                    'imagination is to translate the lyrics of a song you '
                    'know well into solfège. Take it for a spin!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sourceSans3(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            // Dismiss X in the top-right corner of the card.
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
