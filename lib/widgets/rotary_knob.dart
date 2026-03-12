import 'package:flutter/material.dart';
import 'dart:math' as math;

/// A rotary knob widget for controlling continuous parameters
class RotaryKnob extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? unit;
  final int decimals;
  final double size;

  const RotaryKnob({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.unit,
    this.decimals = 2,
    this.size = 80,
  });

  @override
  State<RotaryKnob> createState() => _RotaryKnobState();
}

class _RotaryKnobState extends State<RotaryKnob> {
  double? _startValue;
  double? _startY;

  double get _normalizedValue =>
      (widget.value - widget.min) / (widget.max - widget.min);

  void _handlePanStart(DragStartDetails details) {
    _startValue = widget.value;
    _startY = details.localPosition.dy;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_startValue == null || _startY == null) return;

    final delta = (_startY! - details.localPosition.dy) / 100;
    final range = widget.max - widget.min;
    final newValue = (_startValue! + delta * range).clamp(widget.min, widget.max);
    widget.onChanged(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = widget.value.toStringAsFixed(widget.decimals);
    final displayText = widget.unit != null ? '$displayValue${widget.unit}' : displayValue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _KnobPainter(
                value: _normalizedValue,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          displayText,
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double value;
  final Color color;

  _KnobPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Draw outer ring
    final outerPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, outerPaint);

    // Draw value arc (from 135° to 405°, i.e., 270° sweep)
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const startAngle = 135 * math.pi / 180;
    final sweepAngle = value * 270 * math.pi / 180;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );

    // Draw knob body
    final knobPaint = Paint()
      ..color = Colors.grey.shade100
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 6, knobPaint);

    // Draw indicator line
    final indicatorAngle = startAngle + sweepAngle;
    final indicatorStart = center + Offset(
      math.cos(indicatorAngle) * (radius - 20),
      math.sin(indicatorAngle) * (radius - 20),
    );
    final indicatorEnd = center + Offset(
      math.cos(indicatorAngle) * (radius - 8),
      math.sin(indicatorAngle) * (radius - 8),
    );

    final indicatorPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(indicatorStart, indicatorEnd, indicatorPaint);
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) =>
      value != oldDelegate.value || color != oldDelegate.color;
}
