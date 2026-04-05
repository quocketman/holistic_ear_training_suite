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
        height: size * 1.15, // pointy-top hex is taller than wide
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

    // Show connection visualizer inside the hex.
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

    final vertices = _pointyTopVertices(center, radius);
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
    // Pointy-top vertices (clockwise from top): 0=top, 1=top-right,
    // 2=bottom-right, 3=bottom, 4=bottom-left, 5=top-left.
    //
    // Warm-up (amber):   edges 4→5, 5→0 (left side)
    // Practice (blue):   edges 0→1, 1→2 (right-top side)
    // Challenge (red):   edges 2→3, 3→4 (bottom side)

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

  /// Returns 6 vertices of a pointy-top hexagon, clockwise from top.
  List<Offset> _pointyTopVertices(Offset center, double radius) {
    return List.generate(6, (i) {
      final angle = (pi / 180) * (60 * i - 90); // -90 puts vertex 0 at top
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
