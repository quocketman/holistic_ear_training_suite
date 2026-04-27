import 'package:flutter/material.dart';
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
  final String? title;

  /// When provided, the canvas renders at this size instead of the fixed
  /// layout pixel dimensions. Used for the live on-screen preview.
  final Size? fitToSize;

  const SolfegeSequenceCanvas({
    super.key,
    required this.notes,
    required this.layout,
    this.tokenSize = 80.0,
    this.fitToSize,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final size = fitToSize ?? layout.pixelSize;
    final isPreview = fitToSize != null;
    final titleFontSize = isPreview ? 20.0 : 48.0;

    return Container(
      width: size.width,
      height: size.height,
      color: Colors.black,
      child: Stack(
        children: [
          if (title != null && title!.isNotEmpty)
            Positioned(
              top: isPreview ? 8 : 24,
              left: 0,
              right: 0,
              child: Text(
                title!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ..._positionedTokens(size),
        ],
      ),
    );
  }

  List<Widget> _positionedTokens(Size canvas) {
    if (notes.isEmpty) return const [];

    final positions = _computePositions(canvas);

    final tokens = <Widget>[];
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.isSpacer) continue; // spacers take up position space but render nothing
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
        ),
      ));
    }
    return tokens;
  }

  List<Offset> _computePositions(Size canvas) {
    final chromatics = notes.map((n) => n.totalChromatic).toList();
    // Only real notes affect pitch range (not spacers).
    final realChromatics = [
      for (var i = 0; i < notes.length; i++)
        if (!notes[i].isSpacer) chromatics[i],
    ];
    if (realChromatics.isEmpty) return List.filled(notes.length, Offset.zero);
    final minC = realChromatics.reduce((a, b) => a < b ? a : b);
    final maxC = realChromatics.reduce((a, b) => a > b ? a : b);
    final pitchSpan = (maxC - minC) * tokenSize;

    final timeAxisLength = layout == CanvasLayout.horizontal
        ? canvas.width
        : canvas.height;
    final pitchAxisLength = layout == CanvasLayout.horizontal
        ? canvas.height
        : canvas.width;

    // Time axis: left-aligned (or top-aligned for vertical), one tokenSize step per note.
    final timeStart = tokenSize / 2;

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
