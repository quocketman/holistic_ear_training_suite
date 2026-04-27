import 'package:flutter/material.dart';
import '../utils/solfege_parser.dart';
import 'solfege_hex_token.dart';

enum CanvasLayout {
  horizontal, // 1920×1080: time → x, pitch → y (higher = up)
  vertical,   // 1080×1920: time → y, pitch → x (higher = right)
}

enum CanvasJustify { left, center, right }

extension CanvasLayoutSize on CanvasLayout {
  /// Content area (excluding title).
  Size get contentSize => switch (this) {
        CanvasLayout.horizontal => const Size(1920, 1080),
        CanvasLayout.vertical => const Size(1080, 1920),
      };

  /// Title height added above the content area for export.
  double get titleHeight => 100.0;

  /// Full export size including title area.
  Size get exportSize {
    final content = contentSize;
    return Size(content.width, content.height + titleHeight);
  }
}

class SolfegeSequenceCanvas extends StatelessWidget {
  final List<SolfegeNote> notes;
  final CanvasLayout layout;
  final double tokenSize;
  final String? title;
  final CanvasJustify justify;

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
    this.justify = CanvasJustify.left,
  });

  @override
  Widget build(BuildContext context) {
    final size = fitToSize ?? layout.exportSize;
    final isPreview = fitToSize != null;
    final titleFontSize = isPreview ? 20.0 : 48.0;
    final titleAreaHeight = isPreview ? 30.0 : layout.titleHeight;
    final hasTitle = title != null && title!.isNotEmpty;

    return Container(
      width: size.width,
      height: size.height,
      color: Colors.black,
      child: Stack(
        children: [
          if (hasTitle)
            Positioned(
              top: isPreview ? 4 : 20,
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
          ..._positionedTokens(size, hasTitle ? titleAreaHeight : 0),
        ],
      ),
    );
  }

  /// Compute effective token size that fits everything in the content area.
  double _effectiveTokenSize(Size canvas, double titleOffset) {
    if (notes.isEmpty) return tokenSize;

    final realChromatics = [
      for (var i = 0; i < notes.length; i++)
        if (!notes[i].isSpacer) notes[i].totalChromatic,
    ];
    if (realChromatics.isEmpty) return tokenSize;

    final minC = realChromatics.reduce((a, b) => a < b ? a : b);
    final maxC = realChromatics.reduce((a, b) => a > b ? a : b);
    final pitchRange = maxC - minC;

    final isPreview = fitToSize != null;
    final margin = isPreview ? 20.0 : 80.0;

    final timeAxisLength = (layout == CanvasLayout.horizontal
        ? canvas.width
        : canvas.height - titleOffset) - margin * 2;
    final pitchAxisLength = (layout == CanvasLayout.horizontal
        ? canvas.height - titleOffset
        : canvas.width) - margin * 2;

    final maxFromTime = notes.isNotEmpty ? timeAxisLength / notes.length : tokenSize;
    final maxFromPitch = pitchRange > 0 ? pitchAxisLength / (pitchRange + 1) : pitchAxisLength;

    return [tokenSize, maxFromTime, maxFromPitch].reduce((a, b) => a < b ? a : b);
  }

  List<Widget> _positionedTokens(Size canvas, double titleOffset) {
    if (notes.isEmpty) return const [];

    final ts = _effectiveTokenSize(canvas, titleOffset);
    final positions = _computePositions(canvas, ts, titleOffset);

    final tokens = <Widget>[];
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.isSpacer) continue;
      final p = positions[i];
      tokens.add(Positioned(
        left: p.dx - ts / 2,
        top: p.dy - ts / 2,
        width: ts,
        height: ts,
        child: SolfegeHexToken(
          label: n.syllable,
          chromaticOffset: n.chromaticOffset,
          size: ts,
        ),
      ));
    }
    return tokens;
  }

  List<Offset> _computePositions(Size canvas, double ts, double titleOffset) {
    final chromatics = notes.map((n) => n.totalChromatic).toList();
    final realChromatics = [
      for (var i = 0; i < notes.length; i++)
        if (!notes[i].isSpacer) chromatics[i],
    ];
    if (realChromatics.isEmpty) return List.filled(notes.length, Offset.zero);
    final minC = realChromatics.reduce((a, b) => a < b ? a : b);
    final maxC = realChromatics.reduce((a, b) => a > b ? a : b);
    final pitchSpan = (maxC - minC) * ts;

    final isPreview = fitToSize != null;
    final margin = isPreview ? 20.0 : 80.0;

    final pitchAxisLength = (layout == CanvasLayout.horizontal
        ? canvas.height - titleOffset
        : canvas.width) - margin * 2;
    final timeAxisLength = (layout == CanvasLayout.horizontal
        ? canvas.width
        : canvas.height - titleOffset) - margin * 2;

    // Pitch axis: center the chromatic range within the content area.
    final pitchStart = margin + (pitchAxisLength - pitchSpan) / 2;

    // Time axis: justify left, center, or right.
    final timeSpan = (notes.length - 1) * ts;
    final double timeStart;
    switch (justify) {
      case CanvasJustify.left:
        timeStart = margin + ts / 2;
      case CanvasJustify.center:
        timeStart = margin + (timeAxisLength - timeSpan) / 2;
      case CanvasJustify.right:
        timeStart = margin + timeAxisLength - timeSpan - ts / 2;
    }

    return List.generate(notes.length, (i) {
      final timePos = timeStart + i * ts;
      final pitchOffsetFromMin = (chromatics[i] - minC) * ts;

      switch (layout) {
        case CanvasLayout.horizontal:
          final y = canvas.height - pitchStart - pitchOffsetFromMin;
          return Offset(timePos, y);
        case CanvasLayout.vertical:
          final x = pitchStart + pitchOffsetFromMin;
          return Offset(x, titleOffset + timePos);
      }
    });
  }
}
