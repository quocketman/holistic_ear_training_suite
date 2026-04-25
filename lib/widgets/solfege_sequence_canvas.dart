import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../utils/solfege_parser.dart';
import 'solfege_hex_token.dart';

enum CanvasLayout {
  horizontal, // 1920×1080: time → x, pitch → y (higher = up)
  vertical,   // 1080×1920: time → y, pitch → x (higher = right)
}

extension CanvasLayoutSize on CanvasLayout {
  Size get pixelSize => switch (this) {
        CanvasLayout.horizontal => const Size(1920, 1080),
        CanvasLayout.vertical => const Size(1080, 1920),
      };
}

/// Lays out a sequence of [SolfegeNote] on a fixed-size canvas, with hexagons
/// stepped by [tokenSize] along both axes (matching `ladder_layout`'s
/// "one semitone = tokenSize" rule).
class SolfegeSequenceCanvas extends StatelessWidget {
  final List<SolfegeNote> notes;
  final CanvasLayout layout;
  final double tokenSize;

  const SolfegeSequenceCanvas({
    super.key,
    required this.notes,
    required this.layout,
    this.tokenSize = 80.0,
  });

  @override
  Widget build(BuildContext context) {
    final size = layout.pixelSize;

    return Container(
      width: size.width,
      height: size.height,
      color: Colors.black,
      child: Stack(
        children: _positionedTokens(size),
      ),
    );
  }

  List<Widget> _positionedTokens(Size canvas) {
    if (notes.isEmpty) return const [];

    final positions = _computePositions(canvas);

    final tokens = <Widget>[];
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      final p = positions[i];
      tokens.add(Positioned(
        left: p.dx - tokenSize / 2,
        top: p.dy - tokenSize / 2,
        width: tokenSize,
        height: tokenSize,
        child: SolfegeHexToken(
          label: n.syllable,
          chromaticOffset: n.chromaticOffset,
          size: tokenSize,
          orientation: HexagonOrientation.pointyTop,
        ),
      ));
    }
    return tokens;
  }

  List<Offset> _computePositions(Size canvas) {
    final chromatics = notes.map((n) => n.totalChromatic).toList();
    final minC = chromatics.reduce((a, b) => a < b ? a : b);
    final maxC = chromatics.reduce((a, b) => a > b ? a : b);
    final pitchSpan = (maxC - minC) * tokenSize;

    final timeAxisLength = layout == CanvasLayout.horizontal
        ? canvas.width
        : canvas.height;
    final pitchAxisLength = layout == CanvasLayout.horizontal
        ? canvas.height
        : canvas.width;

    // Time axis: evenly distribute notes with tokenSize step, centered.
    final timeSpan = (notes.length - 1) * tokenSize;
    final timeStart = (timeAxisLength - timeSpan) / 2;

    // Pitch axis: center the chromatic range.
    final pitchStart = (pitchAxisLength - pitchSpan) / 2;

    return List.generate(notes.length, (i) {
      final timePos = timeStart + i * tokenSize;
      // Higher pitch should be visually higher (up in horizontal, right in
      // vertical). In screen coordinates, "up" = smaller y, "right" = larger x.
      final pitchOffsetFromMin = (chromatics[i] - minC) * tokenSize;

      switch (layout) {
        case CanvasLayout.horizontal:
          // y: bottom = lowest, top = highest.
          final y = canvas.height - pitchStart - pitchOffsetFromMin;
          return Offset(timePos, y);
        case CanvasLayout.vertical:
          // x: left = lowest, right = highest.
          final x = pitchStart + pitchOffsetFromMin;
          return Offset(x, timePos);
      }
    });
  }
}
