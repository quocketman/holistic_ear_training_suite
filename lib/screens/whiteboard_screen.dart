import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/enums.dart';
import '../models/musical_state.dart';
import '../models/synth_parameters.dart';
import '../models/tone_token_colors.dart';
import '../services/audio_service.dart';
import '../services/pdf_export.dart'
    show
        exportRepaintBoundaryToPng,
        exportPrintPagesToPdf,
        captureBoundaryToPngBytes;
import '../services/signup_service.dart';
import '../services/url_state.dart';
import '../services/whiteboard_print_layout.dart';
import '../utils/solfege_parser.dart';
import '../utils/score_table.dart';
import '../widgets/score_table_editor.dart';
import '../widgets/solfege_highlight_controller.dart';
import 'sound_design_screen.dart';
import '../widgets/find_the_key_modal.dart';
import '../widgets/print_score_page.dart';
import '../widgets/solfege_hex_token.dart';
import '../widgets/whiteboard_canvas.dart';

class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({super.key});

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  // Persistent state across page navigation. The score is kept as a Markdown
  // table (the durable multi-voice save format).
  static String _persistedMarkdown = '';
  static String _persistedTitle = '';
  static CanvasJustify _persistedJustify = CanvasJustify.left;
  static SolfegeHexTheme _persistedTheme = SolfegeHexTheme.dark;
  static SolfegeTokenShape _persistedShape = SolfegeTokenShape.circle;
  // Session-scoped — resets on page reload. Suppresses the welcome modal
  // after the user has dismissed it once in this browser tab.
  static bool _welcomeShown = false;

  late final SolfegeHighlightController _controller;
  late final TextEditingController _titleController;
  final _canvasKey = GlobalKey();
  // Lets the screen reach into the on-screen preview canvas to read a
  // token's position when the arrow-play playhead moves, so we can keep
  // it scrolled into view.
  final _previewCanvasKey = GlobalKey<WhiteboardCanvasState>();
  final AudioService _audioService = AudioService();
  final Map<int, NoteHandle> _activeNotes = {};
  // Controls the horizontal scroll position of the canvas viewport. We keep
  // it scrolled so the note under the text cursor stays in view — whether the
  // user is appending at the end or editing back in the middle.
  final _canvasScrollController = ScrollController();

  /// User zoom for the on-screen board. 1.0 = "fit the viewport"; larger
  /// values grow the tokens and let the board scroll. Preview only — exports
  /// and the print PDF always render at their own fitted size.
  double _zoom = 1.0;
  static const double _zoomMin = 0.6;
  static const double _zoomMax = 4.0;
  static const double _zoomStep = 0.25;

  void _setZoom(double z) {
    final clamped = z.clamp(_zoomMin, _zoomMax).toDouble();
    if (clamped != _zoom) setState(() => _zoom = clamped);
  }

  // Toggled by the AppBar ? icon. The help panel slides in below the input
  // area as an overlay on the canvas, so users can read the directions while
  // typing.
  bool _isHelpVisible = false;
  // Arrow-key play state. Arrow keys step through BEATS/columns; each step
  // sounds every voice in the column at once (a chord). -1 = no playhead.
  // _playIndex is a representative note index (for scroll + single-tap glow);
  // _playColumn (>= 0 during arrow-play) glows/sounds the whole column.
  int _playIndex = -1;
  int _playColumn = -1;
  // True while the body Focus has play focus (i.e. user pressed PLAY or
  // released a tap). Used to show on-screen arrow buttons on narrow
  // viewports where a hardware keyboard isn't available.
  bool _playEngaged = false;
  final _playFocusNode = FocusNode(debugLabel: 'whiteboard-play');

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
  // The current score — source of truth for rendering, export and the link.
  // The editor takes this as its starting content and owns a working copy;
  // bumping [_editorEpoch] (its key) forces it to rebuild from a fresh table
  // (e.g. after Clear).
  late ScoreTable _scoreTable;
  int _editorEpoch = 0;
  CanvasJustify _justify = CanvasJustify.left;
  SolfegeHexTheme _theme = SolfegeHexTheme.dark;
  SolfegeTokenShape _shape = SolfegeTokenShape.hex;
  bool _exporting = false;
  // While true, the off-screen export canvas renders with the light theme
  // regardless of `_theme`. Set transiently around a PDF download so the
  // print-bound output is always on a white background.
  bool _forceExportLight = false;
  // When non-null, the off-screen export canvas renders at this size
  // instead of [CanvasLayout.exportSize]. Used to retarget PNG exports.
  Size? _exportSizeOverride;

  // Multi-page print (PDF) job. When [_printJob] is non-null, the build
  // renders one off-screen [PrintScorePage] per page (each in its own
  // RepaintBoundary keyed by [_printPageKeys]) so they can be captured to
  // images and assembled into a multi-page letter PDF.
  static const PrintMetrics _printMetrics = PrintMetrics();
  PrintJob? _printJob;
  List<GlobalKey> _printPageKeys = const [];

  @override
  void initState() {
    super.initState();
    // Load the score. Priority: a new `#table=` Markdown link > a legacy
    // `#text=` single-voice link > the in-memory persisted session.
    final tableMd = readTableMarkdownFromUrl();
    final legacyText = readSolfegeTextFromUrl();
    ScoreTable table;
    if (tableMd != null && tableMd.trim().isNotEmpty) {
      table = ScoreTable.fromMarkdown(tableMd);
    } else if (legacyText != null && legacyText.isNotEmpty) {
      table = ScoreTable.fromSolfegeText(legacyText);
    } else if (_persistedMarkdown.isNotEmpty) {
      table = ScoreTable.fromMarkdown(_persistedMarkdown);
    } else {
      table = ScoreTable.empty();
    }
    _scoreTable = table;
    _parsed = table.toParseResult();
    // `_controller` is retained only as the voice-0 text holder for the legacy
    // export footer/link; it no longer drives rendering, so no listener.
    _controller = SolfegeHighlightController(text: table.toSolfegeText());
    _titleController = TextEditingController(text: _persistedTitle);
    _justify = _persistedJustify;
    _theme = _persistedTheme;
    _shape = _persistedShape;
    // Watch play-focus directly. The Focus widget's onFocusChange callback
    // tracks hasFocus, which stays true while a descendant (a TextField)
    // owns focus — so it doesn't fire when the user taps into the input.
    // The FocusNode listener fires on hasPrimaryFocus changes, which IS
    // the signal we want: "are we the active recipient of arrow keys?"
    _playFocusNode.addListener(_onPlayFocusChanged);
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
    _persistedMarkdown = _scoreTable.toMarkdown();
    _persistedTitle = _titleController.text;
    _persistedJustify = _justify;
    _persistedTheme = _theme;
    _persistedShape = _shape;
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
    _playFocusNode.removeListener(_onPlayFocusChanged);
    _playFocusNode.dispose();
    super.dispose();
  }

  int _midiForNote(SolfegeNote note, int tonic) =>
      tonic + note.chromaticOffset + note.octave * 12;

  Future<void> _onNoteDown(int index) async {
    if (index < 0 || index >= _parsed.notes.length) return;
    final note = _parsed.notes[index];
    // No audio for spacers or lyric-only notes — the latter are
    // intentional silent placeholders. The canvas still scales them
    // visually so the user sees their tap registered.
    if (note.isSpacer || note.isLyricOnly) return;
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
    final note = _parsed.notes[index];
    // Tapping a lyric-only note that's currently the arrow-play playhead
    // dismisses it (scales the enlarged syllable back down). Otherwise
    // lyric-only taps don't change play state — they're silent acknowledgments.
    if (note.isLyricOnly) {
      if (_playIndex == index) {
        setState(() => _playIndex = -1);
      }
      return;
    }
    // Pitched tap: only THIS token sounded (via _onNoteDown). Engage play
    // mode from this beat — single-token glow (_playColumn = -1), focus the
    // body so the next ← / → routes to _onPlayKey (and steps by column,
    // sounding the whole chord), and surface the on-screen arrow buttons.
    if (!note.isSpacer) {
      setState(() {
        _playIndex = index;
        _playColumn = -1;
        _playEngaged = true;
      });
      _playFocusNode.requestFocus();
    }
  }

  /// The table editor reports a change. The table is the source of truth: it
  /// drives rendering (toParseResult), the voice-0 legacy text (for the export
  /// footer/link) and the persisted Markdown save.
  void _onTableChanged(ScoreTable table) {
    setState(() {
      _scoreTable = table;
      _parsed = table.toParseResult();
    });
    _controller.text = table.toSolfegeText();
    _persistedMarkdown = table.toMarkdown();
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

  String _exportFilenamePrefix() {
    final title = _titleController.text.trim();
    return title.isNotEmpty
        ? title
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .replaceAll(RegExp(r'\s+'), '_')
        : 'whiteboard';
  }

  /// Common pre/post around a capture — toggles the off-screen canvas to
  /// the requested theme + size and waits a frame so the RepaintBoundary
  /// repaints before [run] captures it.
  Future<void> _runExport({
    required bool forceLight,
    required String label,
    Size? sizeOverride,
    required Future<String> Function() run,
  }) async {
    if (_parsed.notes.isEmpty || _exporting) return;

    // Phase 1 — open the dialog FIRST with no heavy rebuild yet, so the
    // popup-menu's close animation runs smoothly and the user sees
    // "Generating…" immediately instead of a frozen-looking dropdown.
    setState(() => _exporting = true);
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _ExportProgressDialog(label: label),
    );
    // Let the dialog open animation and popup-menu close animation
    // both get frames before we kick off the expensive canvas rebuild.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    // Phase 2 — now flip theme + size. The off-screen canvas rebuilds
    // at letter aspect; the dialog stays visible during the rebuild so
    // there's continuous feedback.
    if (!mounted) return;
    setState(() {
      _forceExportLight = forceLight;
      _exportSizeOverride = sizeOverride;
    });
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    try {
      final destination = await run();
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
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _exporting = false;
          _forceExportLight = false;
          _exportSizeOverride = null;
        });
      }
    }
  }

  /// Print PDF: fixed token size, auto-wrapped systems, flowed across as many
  /// letter pages as needed. Paginates, renders each page off-screen, captures
  /// each to an image, and assembles the multi-page PDF.
  Future<void> _downloadPdf() async {
    if (_parsed.notes.isEmpty || _exporting) return;
    final job = paginate(_parsed.notes, _printMetrics);

    // Phase 1 — show the progress dialog FIRST with no heavy rebuild, and give
    // it frames to actually paint before the expensive page render starts.
    setState(() => _exporting = true);
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => const _ExportProgressDialog(label: 'Generating PDF…'),
    );
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    // Phase 2 — now render the off-screen print pages, then capture them.
    setState(() {
      _printJob = job;
      _printPageKeys = [for (var i = 0; i < job.pageCount; i++) GlobalKey()];
    });
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      final images = <Uint8List>[];
      for (final key in _printPageKeys) {
        images.add(await captureBoundaryToPngBytes(boundaryKey: key));
      }
      final destination = await exportPrintPagesToPdf(
        pageImages: images,
        filenamePrefix: _exportFilenamePrefix(),
        solfegeText: _controller.text,
        title: _titleController.text.trim(),
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
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _exporting = false;
          _printJob = null;
          _printPageKeys = const [];
        });
      }
    }
  }

  Future<void> _downloadPng() => _runExport(
        forceLight: false,
        label: 'Generating PNG…',
        run: () => exportRepaintBoundaryToPng(
          boundaryKey: _canvasKey,
          filenamePrefix: _exportFilenamePrefix(),
        ),
      );

  /// Shows the end-user a preview of exactly what the chosen format will
  /// produce — same multi-row line-break layout, page aspect, and theme as
  /// the real export — before they commit to saving. PDF previews letter
  /// portrait on a white background; PNG previews the on-screen theme at the
  /// layout's native aspect. Save kicks off the existing capture path.
  void _showExportPreview({required bool isPdf}) {
    if (_parsed.notes.isEmpty || _exporting) return;
    final layout = _resolvedLayout(context);

    final Size exportSize;
    final Widget content;
    final String headerLabel;
    if (isPdf) {
      // Preview the first printable page exactly as it will render.
      final job = paginate(_parsed.notes, _printMetrics);
      exportSize = Size(_printMetrics.pageWidth, _printMetrics.pageHeight);
      content = PrintScorePage(
        metrics: _printMetrics,
        page: job.pages.first,
        pageIndex: 0,
        title: _titleController.text.trim(),
        shape: _shape,
      );
      headerLabel = job.pageCount > 1
          ? 'PDF preview — page 1 of ${job.pageCount} (letter)'
          : 'PDF preview — letter';
    } else {
      exportSize = layout.exportSize;
      content = WhiteboardCanvas(
        notes: _parsed.notes,
        layout: layout,
        title: _titleController.text.trim(),
        justify: _justify,
        theme: _theme,
        shape: _shape,
        respectLineBreaks: true,
        sizeOverride: exportSize,
      );
      headerLabel = 'PNG preview — matches current theme';
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => _ExportPreviewDialog(
        exportSize: exportSize,
        content: content,
        headerLabel: headerLabel,
        saveLabel: isPdf ? 'Save PDF' : 'Save PNG',
        onSave: () {
          Navigator.of(ctx).pop();
          if (isPdf) {
            _downloadPdf();
          } else {
            _downloadPng();
          }
        },
      ),
    );
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
                        fontWeight:
                            p == current ? FontWeight.bold : FontWeight.normal,
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

  // ── Play (arrow-key stepping) ─────────────────────────────────────────

  /// Returns the index of the next/prev pitched note from [from], stepping
  /// by [delta] (+1 forward, -1 back). Skips spacers and lyric-only notes.
  /// Returns null if no further pitched note exists in that direction.
  /// Next index the arrow-play stepper should land on. Stops on pitched
  /// notes AND on lyric-only notes (the latter so the user can pause and
  /// imagine the unsung pitch). Skips spacers and line-break markers.

  /// Fires whenever the play-focus node's focus state changes — including
  /// when primary focus moves to a TextField inside the body subtree.
  /// When we lose primary focus, dismiss the playhead glow and the
  /// on-screen step buttons.
  void _onPlayFocusChanged() {
    if (_playFocusNode.hasPrimaryFocus) return;
    if (_playIndex < 0 && _playColumn < 0 && !_playEngaged) return;
    setState(() {
      _playIndex = -1;
      _playColumn = -1;
      _playEngaged = false;
    });
  }

  /// Scrolls the horizontal canvas viewport so the currently-playing
  /// token sits comfortably inside it. No-op when the token is already
  /// visible — we don't want chasing scroll for tokens already on-screen.
  void _scrollToPlayingToken() {
    if (_playIndex < 0 || _playIndex >= _parsed.notes.length) return;
    if (!_canvasScrollController.hasClients) return;
    final pos = _previewCanvasKey.currentState?.tokenPosition(_playIndex);
    if (pos == null) return;

    final position = _canvasScrollController.position;
    final viewport = position.viewportDimension;
    final current = _canvasScrollController.offset;
    final tokenX = pos.dx;
    // Comfort padding so the playhead doesn't sit pressed against the
    // viewport edge (where the on-screen step buttons live).
    const edgePad = 96.0;

    double? target;
    if (tokenX < current + edgePad) {
      // Off-screen left (or too close to the left edge).
      target = tokenX - viewport * 0.3;
    } else if (tokenX > current + viewport - edgePad) {
      // Off-screen right (or too close to the right edge).
      target = tokenX - viewport * 0.7;
    }
    if (target == null) return;

    final clamped = target.clamp(0.0, position.maxScrollExtent);
    _canvasScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Mirrors the user's sound design but with a snappier release so a
  /// previous note doesn't bleed through several rhythm beats while the
  /// next one starts. Fresh instance each step so we can't accidentally
  /// stomp the global params.
  SynthParameters _playParams() {
    final g = AudioService.globalSynthParams;
    return SynthParameters()
      ..oscillatorType = g.oscillatorType
      ..filterCutoff = g.filterCutoff
      ..filterResonance = g.filterResonance
      ..attack = g.attack
      ..decay = g.decay
      ..sustain = g.sustain
      ..release = 0.05; // snappy
  }

  /// Each arrow press fires a note and schedules its release exactly
  /// [_kPlayHoldMs] later. Notes are independent — rapid arrowing produces
  /// overlapping sustains, which sounds natural for legato playing. No
  /// cross-step handle tracking required.
  static const int _kPlayHoldMs = 500;

  /// The ordered, distinct beat/columns that contain a renderable note
  /// (pitched or a silent lyric-only pause). Arrow-play steps through these.
  List<int> _playableColumns() {
    final seen = <int>{};
    final cols = <int>[];
    for (final n in _parsed.notes) {
      if (n.isSpacer || n.isLineBreak || n.column < 0) continue;
      if (seen.add(n.column)) cols.add(n.column);
    }
    return cols;
  }

  /// Advance the playhead by one beat/column and sound EVERY voice in that
  /// column at once (a chord), each on its own synth voice. Tapping still
  /// sounds a single token; this is the arrow-step behaviour.
  Future<void> _stepPlay(int delta) async {
    final cols = _playableColumns();
    if (cols.isEmpty) return;

    final currentCol = _playColumn >= 0
        ? _playColumn
        : (_playIndex >= 0 && _playIndex < _parsed.notes.length
            ? _parsed.notes[_playIndex].column
            : -1);
    final curPos = cols.indexOf(currentCol);
    final targetPos =
        curPos < 0 ? (delta > 0 ? 0 : cols.length - 1) : curPos + delta;

    if (targetPos < 0 || targetPos >= cols.length) {
      // Stepped past the boundary — release the glow; the opposite arrow
      // re-enters at the last/first column via the currentCol fallback.
      setState(() {
        _playColumn = -1;
        _playIndex = delta > 0 ? _parsed.notes.length : -1;
      });
      return;
    }

    final targetCol = cols[targetPos];
    final repIndex = _parsed.notes.indexWhere(
        (n) => n.column == targetCol && !n.isSpacer && !n.isLineBreak);
    setState(() {
      _playColumn = targetCol;
      _playIndex = repIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToPlayingToken();
    });

    // Sound every pitched voice in the column simultaneously.
    final tonic = context.read<MusicalState>().currentTonic;
    for (final n in _parsed.notes) {
      if (n.column != targetCol) continue;
      if (n.isSpacer || n.isLineBreak || n.isLyricOnly) continue;
      final midi = tonic + n.chromaticOffset + n.octave * 12;
      if (midi < 0 || midi > 127) continue;
      final handle = await _audioService.noteOn(midi, params: _playParams());
      if (handle != null) {
        Future.delayed(
            const Duration(milliseconds: _kPlayHoldMs), handle.release);
      }
    }
  }

  /// PLAY button — primes the playhead before the first note and grabs
  /// keyboard focus so the next ↦ arrow press fires note #1.
  void _onPlay() {
    if (_parsed.notes.isEmpty) return;
    setState(() {
      _playIndex = -1;
      _playColumn = -1;
      _playEngaged = true;
    });
    _playFocusNode.requestFocus();
  }

  KeyEventResult _onPlayKey(FocusNode node, KeyEvent event) {
    // The body Focus widget receives bubbled key events from focused
    // descendants too (e.g. a TextField hands ← / → back if the cursor
    // is at a boundary). Only act when arrow-play is actually engaged
    // AND we hold primary focus — otherwise let the event keep bubbling.
    if (!_playEngaged || !_playFocusNode.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _stepPlay(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _stepPlay(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── AppBar action handlers ─────────────────────────────────────────────

  Future<void> _openTuneIndigo() async {
    await launchUrl(Uri.parse('https://tuneindigo.com'));
  }

  // ignore: unused_element — kept ready for the Sound Design re-enable.
  void _openSoundDesign() {
    // Opens the existing sound-design screen. Its edits land directly on
    // AudioService.globalSynthParams, so the Whiteboard's tones inherit
    // the new sound design as soon as the user comes back.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SoundDesignScreen()),
    );
  }

  void _openFindTheKey() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FindTheKeyModal(
        audioService: _audioService,
        theme: _theme,
      ),
    );
  }

  Future<void> _openVideo() async {
    await launchUrl(Uri.parse('https://youtu.be/iQ1DbGv2f9c'));
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

  void _toggleTheme() {
    setState(() {
      _theme = _theme == SolfegeHexTheme.dark
          ? SolfegeHexTheme.light
          : SolfegeHexTheme.dark;
      _persistedTheme = _theme;
    });
  }

  void _toggleShape() {
    setState(() {
      _shape = _shape == SolfegeTokenShape.hex
          ? SolfegeTokenShape.circle
          : SolfegeTokenShape.hex;
      _persistedShape = _shape;
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
          sub: 'Place | at the beginning and ending of the group.',
          example: '| do mi so |',
        ),
        const _HelpItem(
          text: 'Line break (PDF + share)',
          sub: 'Splits the music into stacked rows when you download or share. '
              'The on-screen editor stays one continuous line.',
          example: 'do re mi [] fa so la',
        ),
      ],
    );
  }

  void _clear() {
    _controller.clear();
    _titleController.clear();
    _persistedMarkdown = '';
    _persistedTitle = '';
    setState(() {
      _scoreTable = ScoreTable.empty();
      _parsed = const SolfegeParseResult(notes: [], unrecognized: []);
      _editorEpoch++; // force the table editor to rebuild from the empty table
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = _resolvedLayout(context);
    final canvasSize = _exportSizeOverride ?? layout.exportSize;

    // "so" (Blue, #3F55C7) — chromatic offset 7. AppBar uses this; the
    // bottom signup banner mirrors it so chrome reads as one cohesive frame.
    final chromeColor = ToneTokenColors.getColor(7);
    // Phones + small tablet windows get a stripped-down AppBar — non-
    // essential placeholders and the "watch intro" link drop out so the
    // visible icons don't overlap. 900 px catches phone-landscape and
    // narrow-window desktop testing without affecting the typical
    // full-screen desktop view.
    final isNarrow = MediaQuery.of(context).size.width < 900;
    return Scaffold(
      bottomNavigationBar: _buildSignupBanner(),
      appBar: AppBar(
        backgroundColor: chromeColor,
        foregroundColor: Colors.white,
        title: const Text('Tune Indigo Whiteboard'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: 270,
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
            // Find the Key — ear-only key-finding overlay. Sits next to
            // the key picker so the two key-related affordances cluster
            // visually; the hearing glyph differentiates "by ear" from
            // the dropdown's "by name".
            IconButton(
              icon: const Icon(Icons.hearing),
              tooltip: 'Find the key by ear',
              onPressed: _openFindTheKey,
            ),
            _buildOctavePicker(),
            // PLAY — primes the keyboard playhead. Arrow keys advance/back.
            IconButton(
              icon: const Icon(Icons.play_arrow_outlined),
              tooltip: 'Play — use ← → to step through notes',
              onPressed: _parsed.notes.isEmpty ? null : _onPlay,
            ),
            // Sound Design lives with the audio controls. Disabled while
            // the feature is teased; re-enable by flipping onPressed back.
            const IconButton(
              icon: _KnobIcon(),
              tooltip: 'Sound design (coming soon)',
              onPressed: null,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Download',
            enabled: !(_parsed.notes.isEmpty || _exporting),
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
            onSelected: (value) {
              switch (value) {
                case 'pdf':
                  _showExportPreview(isPdf: true);
                case 'png':
                  _showExportPreview(isPdf: false);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('PDF (white background, print-ready)'),
                ),
              ),
              PopupMenuItem(
                value: 'png',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.image_outlined),
                  title: Text('PNG image (matches current theme)'),
                ),
              ),
            ],
          ),
          if (!isNarrow)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: _onShare,
            ),
          if (!isNarrow)
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
          if (!isNarrow)
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
          IconButton(
            icon: Icon(_shape == SolfegeTokenShape.hex
                ? Icons.circle_outlined
                : Icons.hexagon_outlined),
            tooltip: _shape == SolfegeTokenShape.hex
                ? 'Use circle tokens'
                : 'Use hexagon tokens',
            onPressed: _toggleShape,
          ),
          IconButton(
            icon: Icon(_theme == SolfegeHexTheme.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            tooltip: _theme == SolfegeHexTheme.dark
                ? 'Switch to white background'
                : 'Switch to black background',
            onPressed: _toggleTheme,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Focus(
        focusNode: _playFocusNode,
        // Arrow keys route here while this node holds primary focus. The
        // FocusNode listener (added in initState) is what dismisses the
        // glow + on-screen arrows when a TextField takes primary focus
        // away — onFocusChange would not fire for that case because the
        // TextField lives inside this Focus's subtree.
        onKeyEvent: _onPlayKey,
        child: Stack(
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
                      // Table entry surface (replaces the raw lyrics+solfège text
                      // box). Columns = beats; each voice is a pair of rows
                      // (lyric/placeholder over solfège). Edits serialize back to the
                      // legacy text via _onTableChanged so the render/export/link
                      // pipeline is unchanged.
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ScoreTableEditor(
                          key: ValueKey(_editorEpoch),
                          initialTable: _scoreTable,
                          theme: _theme,
                          onChanged: _onTableChanged,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Expanded(
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
                            _zoomControl(),
                          ],
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
                            scrollDirection: Axis.vertical,
                            // At 1.0 the board is fitted, so vertical dragging stays
                            // available for drag-to-play. Zoomed in, the board is
                            // taller than the viewport and needs to pan.
                            physics: _zoom > 1.0
                                ? const ClampingScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              controller: _canvasScrollController,
                              child: WhiteboardCanvas(
                                key: _previewCanvasKey,
                                notes: _parsed.notes,
                                layout: layout,
                                // Maximum diameter — actual size shrinks to fit
                                // pitch range on narrow viewports. Phones end up at
                                // the pitch-axis ceiling (~35-40 px), iPads grow
                                // into the 80-110 range, desktops cap at 120.
                                tokenSize: 120.0,
                                fitToSize: Size(
                                  constraints.maxWidth - 24,
                                  constraints.maxHeight - 24,
                                ),
                                zoom: _zoom,
                                title: _titleController.text.trim(),
                                justify: _justify,
                                onNoteDown: _onNoteDown,
                                onNoteUp: _onNoteUp,
                                playingIndex: _playIndex,
                                playingColumn: _playColumn,
                                theme: _theme,
                                shape: _shape,
                              ),
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
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: _buildHelpPanel(),
                              ),
                            ),
                          ),
                          // On-screen step buttons during arrow-play. Always shown
                          // when arrow-play is engaged — phones and tablets need
                          // them (no keyboard); desktop users get an extra,
                          // unobtrusive way to step beyond the ← / → keys.
                          if (_playEngaged) ...[
                            Positioned(
                              left: 12,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _PlayStepButton(
                                  icon: Icons.arrow_back,
                                  onPressed: () => _stepPlay(-1),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 12,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _PlayStepButton(
                                  icon: Icons.arrow_forward,
                                  onPressed: () => _stepPlay(1),
                                ),
                              ),
                            ),
                          ],
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
                  theme: _forceExportLight ? SolfegeHexTheme.light : _theme,
                  shape: _shape,
                  respectLineBreaks: true,
                  sizeOverride: _exportSizeOverride,
                ),
              ),
            ),
            // Off-screen print pages for the multi-page PDF export. One
            // RepaintBoundary per page; captured individually then assembled.
            if (_printJob != null)
              Positioned(
                left: -_printMetrics.pageWidth - 100,
                top: -100,
                child: Column(
                  children: [
                    for (var i = 0; i < _printJob!.pages.length; i++)
                      RepaintBoundary(
                        key: _printPageKeys[i],
                        child: PrintScorePage(
                          metrics: _printMetrics,
                          page: _printJob!.pages[i],
                          pageIndex: i,
                          title: _titleController.text.trim(),
                          shape: _shape,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Board size control: shrink / grow the tokens on screen. "Fit" (1.0)
  /// is the old behaviour — the board sized to the viewport. Tapping the
  /// percentage returns to Fit.
  Widget _zoomControl() {
    final dim = Colors.grey[500];
    Widget btn(
        IconData icon, String tip, VoidCallback onPressed, bool enabled) {
      return IconButton(
        tooltip: tip,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: Icon(icon, color: enabled ? dim : Colors.grey[800]),
        onPressed: enabled ? onPressed : null,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('board', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(width: 4),
        btn(Icons.remove, 'Smaller tokens', () => _setZoom(_zoom - _zoomStep),
            _zoom > _zoomMin),
        InkWell(
          onTap: () => _setZoom(1.0),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              _zoom == 1.0 ? 'Fit' : '${(_zoom * 100).round()}%',
              style: TextStyle(fontSize: 12, color: dim),
            ),
          ),
        ),
        btn(Icons.add, 'Bigger tokens', () => _setZoom(_zoom + _zoomStep),
            _zoom < _zoomMax),
      ],
    );
  }

  String _statusLine() {
    if (_controller.text.trim().isEmpty) {
      return 'Type syllables separated by spaces.';
    }
    final parts = <String>[];
    parts.add(
        '${_parsed.notes.length} note${_parsed.notes.length == 1 ? '' : 's'}');
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

/// Modal dialog shown while a PDF or PNG export is in flight. Lives on
/// its own navigator route so it paints above any in-flight popup-menu
/// close animation — users see "Generating PDF…" + progress immediately
/// instead of staring at a frozen-looking dropdown.
/// End-user preview of a pending export. Renders the real export canvas
/// (multi-row line breaks, page aspect, theme) scaled to fit the dialog,
/// with Cancel / Save. Save delegates to the existing capture path.
class _ExportPreviewDialog extends StatelessWidget {
  /// Natural pixel size of [content] — used for the preview's aspect ratio.
  final Size exportSize;

  /// The exact fixed-size content that will be captured (a WhiteboardCanvas
  /// for PNG, a PrintScorePage for PDF). Scaled to fit the dialog.
  final Widget content;
  final String headerLabel;
  final String saveLabel;
  final VoidCallback onSave;

  const _ExportPreviewDialog({
    required this.exportSize,
    required this.content,
    required this.headerLabel,
    required this.saveLabel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final accent = ToneTokenColors.getColor(7); // so-blue
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.size.width * 0.9,
          maxHeight: media.size.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.visibility_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      headerLabel,
                      style: GoogleFonts.sourceSans3(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: exportSize.width / exportSize.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox.fromSize(
                          size: exportSize,
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.sourceSans3(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(saveLabel),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportProgressDialog extends StatelessWidget {
  final String label;
  const _ExportProgressDialog({required this.label});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.file_download_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.sourceSans3(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    ToneTokenColors.getColor(7), // so-blue accent
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Rendering the canvas at full resolution — this usually takes a few seconds.',
                style: GoogleFonts.sourceSans3(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.7),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rotary-knob glyph for the Sound Design AppBar action — a hollow circle
/// with a short indicator tick at the 12-o'clock position. Colour inherits
/// from the surrounding `IconTheme`, so it matches the AppBar's foreground.
class _KnobIcon extends StatelessWidget {
  const _KnobIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.white;
    return CustomPaint(
      size: const Size(22, 22),
      painter: _KnobPainter(color: color),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final Color color;
  const _KnobPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final radius = (size.width / 2) - (stroke / 2) - 0.5;
    canvas.drawCircle(size.center(Offset.zero), radius, paint);

    // Indicator tick at 12 o'clock — sits just inside the ring.
    final tickStart = Offset(size.width / 2, stroke + 1);
    final tickEnd = Offset(size.width / 2, size.height * 0.30);
    canvas.drawLine(tickStart, tickEnd, paint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter old) => old.color != color;
}

/// Floating circular ←/→ step button shown over the canvas during arrow-
/// play on narrow viewports (replacing the missing keyboard). Explicit
/// white border around a translucent dark fill so the circle reads
/// against any underlying token, and a real arrow glyph (not a chevron)
/// so the "step forward / step back" intent is obvious.
class _PlayStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _PlayStepButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Don't steal primary focus from the play FocusNode when tapped —
      // otherwise the listener would think the user left arrow-play mode.
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
      ),
    );
  }
}
