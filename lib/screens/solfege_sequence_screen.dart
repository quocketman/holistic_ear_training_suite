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
  final _titleController = TextEditingController();
  final _canvasKey = GlobalKey();

  SolfegeParseResult _parsed = const SolfegeParseResult(
    notes: [],
    unrecognized: [],
  );
  CanvasLayout? _layoutOverride;
  CanvasJustify _justify = CanvasJustify.left;
  bool _exporting = false;

  @override
  void dispose() {
    _controller.dispose();
    _titleController.dispose();
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
      // Use title for filename, falling back to generic prefix.
      final title = _titleController.text.trim();
      final prefix = title.isNotEmpty
          ? title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_')
          : 'solfege_sequence';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _clear() {
    _controller.clear();
    _titleController.clear();
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
        title: const Text('Solfège Sequence'),
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
      body: Column(
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
                    labelText: 'Solfège sequence',
                    hintText: "e.g. do re mi fa sol la ti do'",
                    helperText:
                        "Suffix ' for octave up, , for octave down (do' do,)",
                  ),
                  textInputAction: TextInputAction.done,
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
                return Center(
                  child: SolfegeSequenceCanvas(
                    notes: _parsed.notes,
                    layout: layout,
                    tokenSize: 50.0,
                    fitToSize: Size(constraints.maxWidth - 24, constraints.maxHeight - 24),
                    title: _titleController.text.trim(),
                    justify: _justify,
                  ),
                );
              },
            ),
          ),
          // Full-res canvas for PNG export — hidden but still laid out.
          ClipRect(
            child: Align(
              alignment: Alignment.topLeft,
              heightFactor: 0.001,
              widthFactor: 0.001,
              child: RepaintBoundary(
                key: _canvasKey,
                child: SizedBox(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: SolfegeSequenceCanvas(
                    notes: _parsed.notes,
                    layout: layout,
                    title: _titleController.text.trim(),
                    justify: _justify,
                  ),
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
