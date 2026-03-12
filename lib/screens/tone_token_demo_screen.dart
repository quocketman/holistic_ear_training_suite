import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_nugget.dart';
import '../models/musical_state.dart';
import '../models/enums.dart';
import '../widgets/tone_token.dart';
import '../services/audio_service.dart';

/// Demo screen to visualize ToneTokens in various layouts
class ToneTokenDemoScreen extends StatefulWidget {
  const ToneTokenDemoScreen({super.key});

  @override
  State<ToneTokenDemoScreen> createState() => _ToneTokenDemoScreenState();
}

class _ToneTokenDemoScreenState extends State<ToneTokenDemoScreen> {
  String _currentLayout = 'vertical';
  final AudioService _audioService = AudioService();

  // Track active notes for sustain/release
  final Map<NoteNugget, NoteHandle> _activeNotes = {};

  // Create a full chromatic scale of NoteNuggets
  // Mapped to proper scale degrees and alterations for all 12 chromatic pitches
  final List<NoteNugget> _chromaticScale = [
    NoteNugget(scaleDegree: 1, chromaticAlteration: 0),   // 0: do (C)
    NoteNugget(scaleDegree: 1, chromaticAlteration: 1),   // 1: di (C#)
    NoteNugget(scaleDegree: 2, chromaticAlteration: 0),   // 2: re (D)
    NoteNugget(scaleDegree: 3, chromaticAlteration: -1),  // 3: me (Eb)
    NoteNugget(scaleDegree: 3, chromaticAlteration: 0),   // 4: mi (E)
    NoteNugget(scaleDegree: 4, chromaticAlteration: 0),   // 5: fa (F)
    NoteNugget(scaleDegree: 4, chromaticAlteration: 1),   // 6: fi (F#)
    NoteNugget(scaleDegree: 5, chromaticAlteration: 0),   // 7: so (G)
    NoteNugget(scaleDegree: 6, chromaticAlteration: -1),  // 8: le (Ab)
    NoteNugget(scaleDegree: 6, chromaticAlteration: 0),   // 9: la (A)
    NoteNugget(scaleDegree: 7, chromaticAlteration: -1),  // 10: te (Bb)
    NoteNugget(scaleDegree: 7, chromaticAlteration: 0),   // 11: ti (B)
  ];

  @override
  Widget build(BuildContext context) {
    final musicalState = context.watch<MusicalState>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('ToneToken Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Musical State Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Musical State',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Current: ${musicalState.toString()}'),
                    const SizedBox(height: 12),
                    
                    // Mode selector
                    DropdownButton<Mode>(
                      value: musicalState.currentMode,
                      isExpanded: true,
                      items: Mode.values.map((mode) {
                        return DropdownMenuItem(
                          value: mode,
                          child: Text(mode.name),
                        );
                      }).toList(),
                      onChanged: (mode) {
                        if (mode != null) {
                          musicalState.currentMode = mode;
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Layout selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Layout',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'vertical',
                          label: Text('Vertical'),
                          icon: Icon(Icons.view_column),
                        ),
                        ButtonSegment(
                          value: 'horizontal',
                          label: Text('Horizontal'),
                          icon: Icon(Icons.view_stream),
                        ),
                      ],
                      selected: {_currentLayout},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _currentLayout = newSelection.first;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // ToneToken Display
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildLayoutWidget(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutWidget() {
    if (_currentLayout == 'vertical') {
      return _buildVerticalLayout();
    } else {
      return _buildHorizontalLayout();
    }
  }

  /// Vertical layout: Two columns, flat-top hexagons
  Widget _buildVerticalLayout() {
    const tokenSize = 80.0;
    const spacing = 2.0; // 2 points between tokens
    const verticalOffset = (tokenSize + spacing) / 2; // Offset for interlocking
    
    return Column(
      children: [
        const Text(
          'Vertical Layout (2 columns, flat-top)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Left column - reversed order (do at bottom)
            Column(
              children: _chromaticScale
                  .asMap()
                  .entries
                  .where((entry) => entry.key % 2 == 0)
                  .toList()
                  .reversed
                  .map((entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.0),
                        child: ToneToken(
                          noteNugget: entry.value,
                          size: tokenSize,
                          orientation: HexagonOrientation.flatTop,
                          onTapDown: () => _onNoteOn(entry.value),
                          onTapUp: () => _onNoteOff(entry.value),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(width: 1), // 1 point horizontal spacing
            // Right column - reversed order (di/ra at bottom), offset vertically
            Padding(
              padding: const EdgeInsets.only(bottom: verticalOffset),
              child: Column(
                children: _chromaticScale
                    .asMap()
                    .entries
                    .where((entry) => entry.key % 2 == 1)
                    .toList()
                    .reversed
                    .map((entry) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1.0),
                          child: ToneToken(
                            noteNugget: entry.value,
                            size: tokenSize,
                            orientation: HexagonOrientation.flatTop,
                            onTapDown: () => _onNoteOn(entry.value),
                            onTapUp: () => _onNoteOff(entry.value),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Horizontal layout: Two rows, pointy-top hexagons
  Widget _buildHorizontalLayout() {
    final halfPoint = (_chromaticScale.length / 2).ceil();
    
    return Column(
      children: [
        const Text(
          'Horizontal Layout (2 rows, pointy-top)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        // Top row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _chromaticScale
                .sublist(0, halfPoint)
                .map((nugget) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ToneToken(
                        noteNugget: nugget,
                        size: 80,
                        orientation: HexagonOrientation.pointyTop,
                        onTapDown: () => _onNoteOn(nugget),
                        onTapUp: () => _onNoteOff(nugget),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Bottom row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _chromaticScale
                .sublist(halfPoint)
                .map((nugget) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ToneToken(
                        noteNugget: nugget,
                        size: 80,
                        orientation: HexagonOrientation.pointyTop,
                        onTapDown: () => _onNoteOn(nugget),
                        onTapUp: () => _onNoteOff(nugget),
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  void _onNoteOn(NoteNugget nugget) async {
    final musicalState = context.read<MusicalState>();
    final solfege = nugget.getBaseSolfege();
    final midiNote = musicalState.getMidiNote(nugget);
    
    // Start the note and store the handle
    final handle = await _audioService.noteOn(midiNote, params: AudioService.globalSynthParams);
    if (handle != null) {
      _activeNotes[nugget] = handle;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Solfège: $solfege | MIDI: $midiNote | '
          'Degree: ${nugget.scaleDegree} | Alt: ${nugget.chromaticAlteration}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onNoteOff(NoteNugget nugget) {
    // Release the note if it's active
    final handle = _activeNotes.remove(nugget);
    handle?.release();
  }
  
  @override
  void dispose() {
    // Release any active notes
    for (final handle in _activeNotes.values) {
      handle.release();
    }
    _activeNotes.clear();
    _audioService.dispose();
    super.dispose();
  }
}
