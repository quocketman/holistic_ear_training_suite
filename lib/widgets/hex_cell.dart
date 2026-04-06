import 'dart:math';
import 'package:flutter/material.dart';
import '../models/hex_grid_cell.dart';
import '../models/enums.dart';
import 'connection_visualizer.dart';

/// A single hexagonal cell in the zoomed-out grid map.
/// Shows a connection visualizer inside and a segmented progress ring border.
class HexCell extends StatelessWidget {
  final HexGridCell cell;
  final VoidCallback? onTap;

  /// Outer dimension of the hex (pointy-top width).
  final double size;

  const HexCell({
    super.key,
    required this.cell,
    this.onTap,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: cell.isUnlocked ? onTap : null,
      child: SizedBox(
        width: size,
        height: size * 0.866, // flat-top hex: height = width * sqrt(3)/2
        child: CustomPaint(
          painter: _HexCellPainter(
            cell: cell,
            size: size,
          ),
          child: _buildInterior(),
        ),
      ),
    );
  }

  Widget _buildInterior() {
    if (!cell.hasLevels) {
      // Future placeholder — empty.
      return const SizedBox.expand();
    }

    if (!cell.isUnlocked) {
      return const Center(
        child: Icon(Icons.lock_outline, color: Colors.white24, size: 28),
      );
    }

    final inARow = cell.column + 1;

    // Column 1: show connection visualizer.
    if (inARow == 1) {
      final rep = cell.representativeLevel!;
      final mode = rep.preferredMode ?? Mode.major;
      return Padding(
        padding: EdgeInsets.all(size * 0.22),
        child: ConnectionVisualizer(
          levelSpecs: rep,
          mode: mode,
        ),
      );
    }

    // Columns 2+: show inARow count as small white hexagons in rows.
    final dotSize = size * 0.14;
    final spacing = dotSize * 0.2;

    // Arrange in rows: 1→1, 2→2, 3→3, 4→2+2, 5→3+2, 6→3+3, 7→3+2+2, 8→3+3+2 (or similar)
    final rows = <int>[];
    var remaining = inARow;
    while (remaining > 0) {
      final rowCount = remaining >= 3 ? 3 : remaining;
      rows.add(rowCount);
      remaining -= rowCount;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows.map((count) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: spacing / 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(count, (i) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing / 2),
                  child: SizedBox(
                    width: dotSize,
                    height: dotSize,
                    child: CustomPaint(painter: _MiniHexPainter()),
                  ),
                );
              }),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Paints the hex background fill and progress ring segments.
class _HexCellPainter extends CustomPainter {
  final HexGridCell cell;
  final double size;

  _HexCellPainter({required this.cell, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final radius = size / 2 * 0.95;

    final vertices = _flatTopVertices(center, radius);
    final path = _pathFromVertices(vertices);

    // Background fill.
    final fillColor = !cell.hasLevels
        ? Colors.white.withValues(alpha: 0.03)
        : cell.isUnlocked
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.04);
    canvas.drawPath(path, Paint()..color = fillColor);

    // Thin base outline.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    if (!cell.hasLevels) return;

    // Progress ring segments.
    // Flat-top vertices (clockwise from right): 0=right, 1=bottom-right,
    // 2=bottom-left, 3=left, 4=top-left, 5=top-right.
    //
    // Warm-up (amber):   edges 4→5, 5→0 (top side)
    // Practice (blue):   edges 0→1, 1→2 (bottom-right side)
    // Challenge (red):   edges 2→3, 3→4 (left-bottom side)

    _drawSegment(canvas, vertices, [4, 5, 0], Colors.amber,
        cleared: cell.warmUpCleared, mastered: cell.warmUpMastered);
    _drawSegment(canvas, vertices, [0, 1, 2], Colors.lightBlueAccent,
        cleared: cell.practiceCleared, mastered: cell.practiceMastered);
    _drawSegment(canvas, vertices, [2, 3, 4], Colors.redAccent,
        cleared: cell.challengeCleared, mastered: cell.challengeMastered);
  }

  void _drawSegment(
    Canvas canvas,
    List<Offset> vertices,
    List<int> vertexIndices,
    Color color, {
    required bool cleared,
    required bool mastered,
  }) {
    final alpha = cleared ? 1.0 : 0.15;
    final strokeWidth = mastered ? 5.0 : 3.5;

    final segmentPath = Path();
    segmentPath.moveTo(vertices[vertexIndices[0]].dx, vertices[vertexIndices[0]].dy);
    for (int i = 1; i < vertexIndices.length; i++) {
      segmentPath.lineTo(vertices[vertexIndices[i]].dx, vertices[vertexIndices[i]].dy);
    }

    canvas.drawPath(
      segmentPath,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Returns 6 vertices of a flat-top hexagon, clockwise from right.
  List<Offset> _flatTopVertices(Offset center, double radius) {
    return List.generate(6, (i) {
      final angle = (60.0 * i) * pi / 180.0; // 0° puts vertex 0 at right
      return Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
    });
  }

  Path _pathFromVertices(List<Offset> vertices) {
    final path = Path()..moveTo(vertices[0].dx, vertices[0].dy);
    for (int i = 1; i < vertices.length; i++) {
      path.lineTo(vertices[i].dx, vertices[i].dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HexCellPainter old) => true;
}

class _MiniHexPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 * 0.9;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (60.0 * i) * pi / 180.0;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
