import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../models/musical_state.dart';
import '../services/audio_service.dart';
import '../services/png_export.dart';
import '../utils/solfege_parser.dart';
import '../widgets/solfege_sequence_canvas.dart';

class SolfegeSequenceScreen extends StatefulWidget {
  const SolfegeSequenceScreen({super.key});

  @override
  State<SolfegeSequenceScreen> createState() => _SolfegeSequenceScreenState();
}

class _SolfegeSequenceScreenState extends State<SolfegeSequenceScreen> {
  final _controller = TextEditingController();
  final _canvasKey = GlobalKey();
  final AudioService _audioService = AudioService();
  final Map<int, NoteHandle> _activeNotes = {};

  SolfegeParseResult _parsed = const SolfegeParseResult(
    notes: [],
    unrecognized: [],
  );
  CanvasLayout? _layoutOverride;
  bool _exporting = false;

  @override
  void dispose() {
    for (final h in _activeNotes.values) {
      h.release();
    }
    _activeNotes.clear();
    _audioService.dispose();
    _controller.dispose();
    super.dispose();
  }

  int _midiForNote(SolfegeNote note, int tonic) =>
      tonic + note.chromaticOffset + note.octave * 12;

  Future<void> _onNoteDown(int index) async {
    if (index < 0 || index >= _parsed.notes.length) return;
    final tonic = context.read<MusicalState>().currentTonic;
    final midi = _midiForNote(_parsed.notes[index], tonic);
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

  void _setTonicPitchClass(PitchClass pc) {
    final state = context.read<MusicalState>();
    final currentOctave = (state.currentTonic ~/ 12) - 1;
    final newTonic = pc.value + (currentOctave + 1) * 12;
    state.currentTonic = newTonic.clamp(0, 127);
  }

  void _shiftOctave(int delta) {
    final state = context.read<MusicalState>();
    final next = state.currentTonic + delta * 12;
    if (next < 0 || next > 127) return;
    state.currentTonic = next;
  }

  void _onInputChanged(String value) {
    setState(() {
      _parsed = SolfegeParser.parse(value);
    });
  }

  CanvasLayout _resolvedLayout(BuildContext context) {
    if (_layoutOverride != null) return _layoutOverride!;
    return MediaQuery.of(context).orientation == Orientation.portrait
        ? CanvasLayout.vertical
        : CanvasLayout.horizontal;
  }

  Future<void> _print() async {
    if (_parsed.notes.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final destination = await exportRepaintBoundaryToPng(
        boundaryKey: _canvasKey,
        filenamePrefix: 'solfege_sequence',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $destination')),
      );
      _controller.clear();
      setState(() {
        _parsed = const SolfegeParseResult(notes: [], unrecognized: []);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = _resolvedLayout(context);
    final canvasSize = layout.pixelSize;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Solfège Sequence'),
        actions: [
          PopupMenuButton<CanvasLayout?>(
            icon: const Icon(Icons.aspect_ratio),
            tooltip: 'Canvas layout',
            onSelected: (v) => setState(() => _layoutOverride = v),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: null,
                child: Text('Auto (follows orientation)'),
              ),
              const PopupMenuItem(
                value: CanvasLayout.horizontal,
                child: Text('Horizontal 1920×1080'),
              ),
              const PopupMenuItem(
                value: CanvasLayout.vertical,
                child: Text('Vertical 1080×1920'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  onChanged: _onInputChanged,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Solfège sequence',
                    hintText: "e.g. do re mi fa sol la ti do'",
                    helperText:
                        "Suffix ' for octave up, , for octave down (do' do,)",
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 8),
                _buildControlsRow(),
                const SizedBox(height: 4),
                Text(
                  _statusLine(),
                  style: TextStyle(
                    color: _parsed.unrecognized.isNotEmpty
                        ? Colors.redAccent
                        : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: RepaintBoundary(
                  key: _canvasKey,
                  child: SizedBox(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    child: SolfegeSequenceCanvas(
                      notes: _parsed.notes,
                      layout: layout,
                      onNoteDown: _onNoteDown,
                      onNoteUp: _onNoteUp,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsRow() {
    return Consumer<MusicalState>(
      builder: (context, state, _) {
        final pc = state.currentTonicPitchClass;
        final octave = (state.currentTonic ~/ 12) - 1;
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _keyDropdown(pc),
            _octaveStepper(octave),
            FilledButton.icon(
              onPressed:
                  _parsed.notes.isEmpty || _exporting ? null : _print,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print),
              label: const Text('Print PNG'),
            ),
          ],
        );
      },
    );
  }

  Widget _keyDropdown(PitchClass pc) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('do = ', style: TextStyle(fontSize: 14)),
        DropdownButton<PitchClass>(
          value: pc,
          underline: const SizedBox.shrink(),
          items: PitchClass.values
              .map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p.displayName),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) _setTonicPitchClass(v);
          },
        ),
      ],
    );
  }

  Widget _octaveStepper(int octave) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Oct ', style: TextStyle(fontSize: 14)),
        IconButton(
          tooltip: 'Octave down',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => _shiftOctave(-1),
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 24,
          child: Text(
            '$octave',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        IconButton(
          tooltip: 'Octave up',
          icon: const Icon(Icons.keyboard_arrow_up),
          onPressed: () => _shiftOctave(1),
          visualDensity: VisualDensity.compact,
        ),
      ],
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
