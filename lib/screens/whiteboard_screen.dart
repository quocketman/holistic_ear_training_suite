import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/musical_state.dart';
import '../models/tone_token_colors.dart';
import '../services/audio_service.dart';
import '../services/png_export.dart';
import '../services/signup_service.dart';
import '../utils/solfege_parser.dart';
import '../widgets/key_octave_controls.dart';
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

  late final SolfegeHighlightController _controller;
  late final TextEditingController _titleController;
  final _canvasKey = GlobalKey();
  final AudioService _audioService = AudioService();
  final Map<int, NoteHandle> _activeNotes = {};
  // Controls the horizontal scroll position of the canvas viewport. After
  // each input change we jump to maxScrollExtent so the most recently typed
  // tokens are always visible at the right edge.
  final _canvasScrollController = ScrollController();
  // Used to programmatically open the help drawer from the AppBar ? button.
  final _scaffoldKey = GlobalKey<ScaffoldState>();
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
    _controller = SolfegeHighlightController(text: _persistedSolfege);
    _titleController = TextEditingController(text: _persistedTitle);
    _justify = _persistedJustify;
    if (_persistedSolfege.isNotEmpty) {
      _parsed = SolfegeParser.parse(_persistedSolfege);
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

  Future<void> _print() async {
    if (_parsed.notes.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      // Use title for filename, falling back to generic prefix.
      final title = _titleController.text.trim();
      final prefix = title.isNotEmpty
          ? title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_')
          : 'whiteboard';
      final destination = await exportRepaintBoundaryToPng(
        boundaryKey: _canvasKey,
        filenamePrefix: prefix,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $destination')),
      );
    } catch (e) {
      if (!mounted) return;
      // Quietly ignore user-cancelled save dialogs.
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

  // ── AppBar action handlers (most are stubs for now) ────────────────────

  void _onPlayPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Play coming soon')),
    );
  }

  Future<void> _onContact() async {
    final uri = Uri.parse(
        'mailto:hans@tuneindigo.com?subject=Whiteboard%20feedback');
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open mail app')),
      );
    }
  }

  void _onShare() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share coming soon')),
    );
  }

  void _onShowHelp() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _onSignup() {
    // Shortcut from the AppBar — drop the cursor into the persistent
    // banner's email field. (The banner already lives at the bottom of
    // every screen, so this is the most direct affordance.)
    _signupEmailFocus.requestFocus();
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
    _signupFeedbackTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _signupFeedback = null);
    });
  }

  // ── Persistent signup banner ──────────────────────────────────────────

  Widget _buildSignupBanner() {
    // "te" (Violet, #7A1DFF) — chromatic offset 10 in the palette.
    final teColor = ToneTokenColors.getColor(10);
    final headline = _signupFeedback ?? 'Weekly lessons in your inbox';
    final headlineColor = _signupFeedback != null && _signupFeedbackIsError
        ? Colors.amber.shade100
        : Colors.white;

    return Material(
      color: teColor,
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
                  foregroundColor: teColor,
                  disabledBackgroundColor: Colors.white70,
                  disabledForegroundColor: teColor.withValues(alpha: 0.6),
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
                          color: teColor,
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

  Widget _buildHelpDrawer() {
    // "so" (Blue, #3F55C7) — chromatic offset 7 in the Tune Indigo palette.
    // Blue is the brand-fit and universal "info" color; white text gives
    // ~12:1 contrast, exceeding WCAG AAA.
    final drawerBg = ToneTokenColors.getColor(7);
    return Drawer(
      backgroundColor: drawerBg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
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
            const SizedBox(height: 24),
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
        ),
      ),
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

    // "te" (Violet, #7A1DFF) — primary Tune Indigo chrome colour.
    final chromeColor = ToneTokenColors.getColor(10);
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildHelpDrawer(),
      bottomNavigationBar: _buildSignupBanner(),
      appBar: AppBar(
        backgroundColor: chromeColor,
        foregroundColor: Colors.white,
        title: const Text('Tune Indigo Whiteboard'),
        centerTitle: true,
        // Don't auto-show the burger icon — the ? button is the only entry
        // point to the drawer.
        automaticallyImplyLeading: false,
        actions: [
          // Justify buttons.
          IconButton(
            icon: const Icon(Icons.format_align_left),
            color: _justify == CanvasJustify.left ? Colors.white : Colors.white38,
            tooltip: 'Left',
            onPressed: () => setState(() => _justify = CanvasJustify.left),
          ),
          IconButton(
            icon: const Icon(Icons.format_align_center),
            color: _justify == CanvasJustify.center ? Colors.white : Colors.white38,
            tooltip: 'Center',
            onPressed: () => setState(() => _justify = CanvasJustify.center),
          ),
          IconButton(
            icon: const Icon(Icons.format_align_right),
            color: _justify == CanvasJustify.right ? Colors.white : Colors.white38,
            tooltip: 'Right',
            onPressed: () => setState(() => _justify = CanvasJustify.right),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear',
            onPressed: _parsed.notes.isEmpty && _titleController.text.isEmpty
                ? null
                : _clear,
          ),
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.print),
            tooltip: 'Print PNG',
            onPressed: _parsed.notes.isEmpty || _exporting ? null : _print,
          ),

          // Visual divider between tool icons (left) and meta icons (right).
          const SizedBox(width: 24),

          IconButton(
            icon: const Icon(Icons.play_arrow_outlined),
            tooltip: 'Play (coming soon)',
            onPressed: _onPlayPlaceholder,
          ),
          IconButton(
            icon: const Icon(Icons.alternate_email),
            tooltip: 'Send feedback',
            onPressed: _onContact,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share',
            onPressed: _onShare,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How to use',
            onPressed: _onShowHelp,
          ),
          IconButton(
            icon: const Icon(Icons.email_outlined),
            tooltip: 'Subscribe to updates',
            onPressed: _onSignup,
          ),
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
                const SizedBox(height: 8),
                const KeyOctaveControls(),
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
                return SingleChildScrollView(
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
