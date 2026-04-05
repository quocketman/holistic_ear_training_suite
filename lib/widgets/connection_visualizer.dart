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

  const ConnectionVisualizer({
    super.key,
    required this.levelSpecs,
    required this.mode,
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
        // Scale dot size relative to widget — roughly 1/5 of width.
        final dotSize = size.width * 0.22;

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

  _ConnectionPainter({
    required this.slots,
    required this.positions,
    required this.allowedMotions,
    required this.mode,
    required this.dotSize,
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
        canvas.drawCircle(center, radius, Paint()..color = color);
      } else {
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainter old) =>
      old.slots != slots || old.allowedMotions != allowedMotions;
}
