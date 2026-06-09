import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/musical_state.dart';
import '../services/audio_service.dart';
import '../services/png_export.dart';
import '../utils/solfege_parser.dart';
import '../widgets/key_octave_controls.dart';
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

  late final TextEditingController _controller;
  late final TextEditingController _titleController;
  final _canvasKey = GlobalKey();
  final AudioService _audioService = AudioService();
  final Map<int, NoteHandle> _activeNotes = {};

  SolfegeParseResult _parsed = const SolfegeParseResult(
    notes: [],
    unrecognized: [],
  );
  CanvasJustify _justify = CanvasJustify.left;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _persistedSolfege);
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Whiteboard'),
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
                    helperText:
                        "lyric/solfège  •  bare known syllables (do, re, …) → hex  •  bare other words → lyric only  •  trailing / forces lyric  •  ' , raise/lower octave  •  _ spacer  •  | … | groups",
                  ),
                  textInputAction: TextInputAction.done,
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
                return Center(
                  child: WhiteboardCanvas(
                    notes: _parsed.notes,
                    layout: layout,
                    tokenSize: 50.0,
                    fitToSize: Size(constraints.maxWidth - 24, constraints.maxHeight - 24),
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
