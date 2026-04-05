import 'dart:math';
import 'package:flutter/material.dart';
import '../models/level_specs.dart';
import '../models/enums.dart';
import '../models/tone_token_colors.dart';
import '../utils/ladder_layout.dart';

/// Displays colored dots for available notes with white lines showing
/// allowed melodic motions between them. Uses the alternating ladder layout.
///
/// Scales to any size — use small for menu thumbnails, large for game board.
class ConnectionVisualizer extends StatelessWidget {
  final LevelSpecs levelSpecs;
  final Mode mode;
  final bool showOutlines;

  const ConnectionVisualizer({
    super.key,
    required this.levelSpecs,
    required this.mode,
    this.showOutlines = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final slots = buildLadderSlots(
          availableNotes: levelSpecs.availableNoteNuggets,
          mode: mode,
          widestChromaticRange: levelSpecs.widestChromaticRange,
        );

        // Scale dot size to fit: available height = dotSize + semitones * dotSize
        // so dotSize = availableHeight / (1 + totalSemitones).
        final totalSemitones = slots.isNotEmpty ? slots.last.semitoneFromBottom : 0;
        final maxDotFromHeight = totalSemitones > 0
            ? size.height / (1 + totalSemitones)
            : size.height * 0.3;
        final maxDotFromWidth = size.width * 0.35;
        final dotSize = min(maxDotFromHeight, maxDotFromWidth);

        final positions = positionsForSlots(
          slots: slots,
          size: size,
          tokenSize: dotSize,
        );

        return CustomPaint(
          size: size,
          painter: _ConnectionPainter(
            slots: slots,
            positions: positions,
            allowedMotions: levelSpecs.allowedMotions,
            mode: mode,
            dotSize: dotSize,
            showOutlines: showOutlines,
          ),
        );
      },
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  final List<LadderSlot> slots;
  final List<Offset> positions;
  final List<List<int>> allowedMotions;
  final Mode mode;
  final double dotSize;
  final bool showOutlines;

  _ConnectionPainter({
    required this.slots,
    required this.positions,
    required this.allowedMotions,
    required this.mode,
    required this.dotSize,
    required this.showOutlines,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Build a lookup: scaleDegree → position index (use first match per degree).
    final degreeToIndex = <int, int>{};
    for (int i = 0; i < slots.length; i++) {
      final degree = slots[i].nugget.scaleDegree;
      if (!degreeToIndex.containsKey(degree)) {
        degreeToIndex[degree] = i;
      }
    }

    // Draw connection lines first (behind dots).
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final motion in allowedMotions) {
      if (motion.length < 2) continue;
      final fromIdx = degreeToIndex[motion[0]];
      final toIdx = degreeToIndex[motion[1]];
      if (fromIdx == null || toIdx == null) continue;
      canvas.drawLine(positions[fromIdx], positions[toIdx], linePaint);
    }

    // Draw dots on top.
    for (int i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final center = positions[i];
      final radius = dotSize / 2;

      if (slot.isActive) {
        final chromaticOffset = slot.nugget.getChromaticOffset(mode);
        final color = ToneTokenColors.getColor(chromaticOffset);
        final hexPath = _flatTopHexPath(center, radius);
        canvas.drawPath(hexPath, Paint()..color = color);
        if (showOutlines) {
          canvas.drawPath(
            hexPath,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0,
          );
        }
      }
      // Skip ghost dots — too noisy at small sizes.
    }
  }

  /// Flat-top hexagon path centered at [center] with the given [radius].
  Path _flatTopHexPath(Offset center, double radius) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (60.0 * i) * pi / 180.0;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainter old) =>
      old.slots != slots || old.allowedMotions != allowedMotions;
}
