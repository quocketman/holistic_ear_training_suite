import 'package:flutter/material.dart';

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

  SolfegeParseResult _parsed = const SolfegeParseResult(
    notes: [],
    unrecognized: [],
  );
  CanvasLayout? _layoutOverride;
  bool _exporting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _statusLine(),
                        style: TextStyle(
                          color: _parsed.unrecognized.isNotEmpty
                              ? Colors.redAccent
                              : Colors.grey[400],
                        ),
                      ),
                    ),
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
                ),
              ],
            ),
          ),
          // Live preview — fills available space.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: SolfegeSequenceCanvas(
                    notes: _parsed.notes,
                    layout: layout,
                    tokenSize: 50.0,
                    fitToSize: Size(constraints.maxWidth - 24, constraints.maxHeight - 24),
                  ),
                );
              },
            ),
          ),
          // Off-screen full-res canvas for PNG export.
          Offstage(
            child: RepaintBoundary(
              key: _canvasKey,
              child: SizedBox(
                width: canvasSize.width,
                height: canvasSize.height,
                child: SolfegeSequenceCanvas(
                  notes: _parsed.notes,
                  layout: layout,
                ),
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
