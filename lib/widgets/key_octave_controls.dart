import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../models/musical_state.dart';

/// Tonic key + octave controls bound to [MusicalState.currentTonic].
///
/// Renders a dropdown whose button shows the current state as "do = X"
/// (e.g. `do = C♯`), and a MIDI-controller-style octave -/+ stepper.
class KeyOctaveControls extends StatelessWidget {
  const KeyOctaveControls({super.key});

  /// Project convention: octave 0 = the octave where MIDI 48 sits
  /// (the "middle do" octave). MIDI tonic = pitchClass + (octave + 4) * 12.
  static const int _octaveOffset = 4;

  void _setTonicPitchClass(MusicalState state, PitchClass pc) {
    final currentDisplayOctave = (state.currentTonic ~/ 12) - _octaveOffset;
    final newTonic = pc.value + (currentDisplayOctave + _octaveOffset) * 12;
    state.currentTonic = newTonic.clamp(0, 127);
  }

  void _shiftOctave(MusicalState state, int delta) {
    final next = state.currentTonic + delta * 12;
    if (next < 0 || next > 127) return;
    state.currentTonic = next;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicalState>(
      builder: (context, state, _) {
        final pc = state.currentTonicPitchClass;
        final octave = (state.currentTonic ~/ 12) - _octaveOffset;
        return Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _keyDropdown(state, pc),
            _octaveStepper(state, octave),
          ],
        );
      },
    );
  }

  Widget _keyDropdown(MusicalState state, PitchClass current) {
    return DropdownButton<PitchClass>(
      value: current,
      underline: const SizedBox.shrink(),
      // Items in the menu show only the pitch class.
      items: PitchClass.values
          .map((p) => DropdownMenuItem(
                value: p,
                child: Text(p.displayName),
              ))
          .toList(),
      // Button (selected) display shows "do = X".
      selectedItemBuilder: (_) => PitchClass.values
          .map((p) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'do = ${p.displayName}',
                  style: const TextStyle(fontSize: 14),
                ),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) _setTonicPitchClass(state, v);
      },
    );
  }

  Widget _octaveStepper(MusicalState state, int octave) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Oct ', style: TextStyle(fontSize: 14)),
        IconButton(
          tooltip: 'Octave down',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => _shiftOctave(state, -1),
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
          onPressed: () => _shiftOctave(state, 1),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
