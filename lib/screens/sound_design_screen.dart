import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_nugget.dart';
import '../models/musical_state.dart';
import '../models/synth_parameters.dart';
import '../models/enums.dart';
import '../widgets/tone_token.dart';
import '../widgets/rotary_knob.dart';
import '../widgets/parameter_slider.dart';
import '../widgets/oscillator_switch.dart';
import '../widgets/key_octave_controls.dart';
import '../services/audio_service.dart';

/// Sound Design screen with ToneToken keyboard and synth controls
class SoundDesignScreen extends StatefulWidget {
  const SoundDesignScreen({super.key});

  @override
  State<SoundDesignScreen> createState() => _SoundDesignScreenState();
}

class _SoundDesignScreenState extends State<SoundDesignScreen> {
  final AudioService _audioService = AudioService();
  
  // Use the global synth parameters so changes persist
  SynthParameters get _synthParams => AudioService.globalSynthParams;

  // Track active notes for sustain/release
  final Map<NoteNugget, NoteHandle> _activeNotes = {};

  // Chromatic scale of NoteNuggets
  final List<NoteNugget> _chromaticScale = [
    NoteNugget(scaleDegree: 1, chromaticAlteration: 0),
    NoteNugget(scaleDegree: 1, chromaticAlteration: 1),
    NoteNugget(scaleDegree: 2, chromaticAlteration: 0),
    NoteNugget(scaleDegree: 3, chromaticAlteration: -1),
    NoteNugget(scaleDegree: 3, chromaticAlteration: 0),
    NoteNugget(scaleDegree: 4, chromaticAlteration: 0),
    NoteNugget(scaleDegree: 4, chromaticAlteration: 1),
    NoteNugget(scaleDegree: 5, chromaticAlteration: 0),
    NoteNugget(scaleDegree: 6, chromaticAlteration: -1),
    NoteNugget(scaleDegree: 6, chromaticAlteration: 0),
    NoteNugget(scaleDegree: 7, chromaticAlteration: -1),
    NoteNugget(scaleDegree: 7, chromaticAlteration: 0),
  ];

  // GlobalKeys for finding each token's screen bounds (drag-to-play hit-test).
  late final Map<NoteNugget, GlobalKey> _tokenKeys = {
    for (final n in _chromaticScale) n: GlobalKey(),
  };

  // Currently pressed note (drives glowing visual + audio).
  NoteNugget? _pressedNugget;
  bool _pointerDown = false;

  /// Find the token under a global pointer position.
  NoteNugget? _hitTest(Offset globalPos) {
    for (final entry in _tokenKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      if (rect.contains(globalPos)) return entry.key;
    }
    return null;
  }

  void _setPressed(NoteNugget? newNugget) {
    if (newNugget == _pressedNugget) return;
    if (_pressedNugget != null) {
      _onNoteOff(_pressedNugget!);
    }
    if (newNugget != null && _pointerDown) {
      _onNoteOn(newNugget);
    }
    setState(() => _pressedNugget = newNugget);
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointerDown = true;
    final hit = _hitTest(e.position);
    if (hit != null) {
      _onNoteOn(hit);
      setState(() => _pressedNugget = hit);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointerDown) return;
    _setPressed(_hitTest(e.position));
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointerDown = false;
    if (_pressedNugget != null) {
      _onNoteOff(_pressedNugget!);
    }
    setState(() => _pressedNugget = null);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointerDown = false;
    if (_pressedNugget != null) {
      _onNoteOff(_pressedNugget!);
    }
    setState(() => _pressedNugget = null);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _synthParams,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sound Design'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _synthParams.reset(),
              tooltip: 'Reset to defaults',
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: const KeyOctaveControls(),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Use horizontal layout on wide screens
                  if (constraints.maxWidth > 700) {
                    return _buildWideLayout();
                  } else {
                    return _buildNarrowLayout();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wide layout: ToneTokens on left, controls on right
  Widget _buildWideLayout() {
    return Row(
      children: [
        // ToneToken keyboard
        Expanded(
          flex: 1,
          child: Center(
            child: _buildToneTokenKeyboard(),
          ),
        ),
        // Controls panel
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(
              left: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: _buildControlsPanel(),
        ),
      ],
    );
  }

  /// Narrow layout: ToneTokens on top, controls below
  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildToneTokenKeyboard(),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: _buildControlsPanel(),
          ),
        ],
      ),
    );
  }

  /// Build the ToneToken vertical keyboard layout
  Widget _buildToneTokenKeyboard() {
    const tokenSize = 70.0;
    const verticalOffset = (tokenSize + 2) / 2;

    Widget buildTile(NoteNugget nugget) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.0),
        child: IgnorePointer(
          // Pointer events are handled by the Listener wrapper below.
          child: ToneToken(
            key: _tokenKeys[nugget],
            noteNugget: nugget,
            size: tokenSize,
            orientation: HexagonOrientation.flatTop,
            glowing: nugget == _pressedNugget,
          ),
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Left column
              Column(
                children: _chromaticScale
                    .asMap()
                    .entries
                    .where((entry) => entry.key % 2 == 0)
                    .toList()
                    .reversed
                    .map((entry) => buildTile(entry.value))
                    .toList(),
              ),
              const SizedBox(width: 1),
              // Right column (offset)
              Padding(
                padding: const EdgeInsets.only(bottom: verticalOffset),
                child: Column(
                  children: _chromaticScale
                      .asMap()
                      .entries
                      .where((entry) => entry.key % 2 == 1)
                      .toList()
                      .reversed
                      .map((entry) => buildTile(entry.value))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build the synth controls panel
  Widget _buildControlsPanel() {
    return Consumer<SynthParameters>(
      builder: (context, params, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Oscillator type
              OscillatorSwitch(
                value: params.oscillatorType,
                onChanged: (type) => params.oscillatorType = type,
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Filter section
              const Text(
                'Filter',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  RotaryKnob(
                    label: 'Cutoff',
                    value: params.filterCutoff,
                    onChanged: (v) => params.filterCutoff = v,
                    size: 70,
                  ),
                  RotaryKnob(
                    label: 'Resonance',
                    value: params.filterResonance,
                    onChanged: (v) => params.filterResonance = v,
                    size: 70,
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // ADSR section
              const Text(
                'Envelope (ADSR)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ParameterSlider(
                    label: 'A',
                    value: params.attack,
                    min: 0.001,
                    max: 2.0,
                    onChanged: (v) => params.attack = v,
                    unit: 's',
                  ),
                  ParameterSlider(
                    label: 'D',
                    value: params.decay,
                    min: 0.001,
                    max: 2.0,
                    onChanged: (v) => params.decay = v,
                    unit: 's',
                  ),
                  ParameterSlider(
                    label: 'S',
                    value: params.sustain,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => params.sustain = v,
                  ),
                  ParameterSlider(
                    label: 'R',
                    value: params.release,
                    min: 0.001,
                    max: 3.0,
                    onChanged: (v) => params.release = v,
                    unit: 's',
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Parameter display
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  params.toString(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onNoteOn(NoteNugget nugget) async {
    final musicalState = context.read<MusicalState>();
    final midiNote = musicalState.getMidiNote(nugget);

    // Start the note and store the handle
    final handle = await _audioService.noteOn(midiNote, params: _synthParams);
    if (handle != null) {
      _activeNotes[nugget] = handle;
    }

    print('Note on: $midiNote with params: $_synthParams');
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
    // Don't dispose _synthParams - it's the global instance
    super.dispose();
  }
}
