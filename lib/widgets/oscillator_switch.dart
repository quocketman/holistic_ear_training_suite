import 'package:flutter/material.dart';
import '../models/synth_parameters.dart';

/// A segmented control for selecting oscillator type
class OscillatorSwitch extends StatelessWidget {
  final OscillatorType value;
  final ValueChanged<OscillatorType> onChanged;

  const OscillatorSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Oscillator',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<OscillatorType>(
          segments: const [
            ButtonSegment(
              value: OscillatorType.sine,
              label: Text('Sine'),
              icon: Icon(Icons.waves, size: 16),
            ),
            ButtonSegment(
              value: OscillatorType.square,
              label: Text('Square'),
              icon: Icon(Icons.square_outlined, size: 16),
            ),
            ButtonSegment(
              value: OscillatorType.triangle,
              label: Text('Triangle'),
              icon: Icon(Icons.change_history, size: 16),
            ),
          ],
          selected: {value},
          onSelectionChanged: (Set<OscillatorType> selected) {
            onChanged(selected.first);
          },
          showSelectedIcon: false,
        ),
      ],
    );
  }
}
