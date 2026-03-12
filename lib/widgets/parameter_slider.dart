import 'package:flutter/material.dart';

/// A vertical slider with label for ADSR parameters
class ParameterSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? unit;
  final int decimals;

  const ParameterSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.unit,
    this.decimals = 2,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.toStringAsFixed(decimals);
    final displayText = unit != null ? '$displayValue$unit' : displayValue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          displayText,
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
