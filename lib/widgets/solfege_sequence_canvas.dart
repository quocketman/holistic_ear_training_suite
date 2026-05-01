import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  final void Function(int index)? onNoteDown;
  final void Function(int index)? onNoteUp;

  const SolfegeSequenceCanvas({
    super.key,
    required this.notes,
    required this.layout,
    this.tokenSize = 80.0,
    this.onNoteDown,
    this.onNoteUp,
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
    final lyrics = <Widget>[];
    final lyricStyle = GoogleFonts.sourceSans3(
      fontSize: tokenSize * 0.22,
      fontWeight: FontWeight.w500,
      color: Colors.white,
      height: 1.0,
    );

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
          onTapDown: onNoteDown == null ? null : () => onNoteDown!(i),
          onTapUp: onNoteUp == null ? null : () => onNoteUp!(i),
        ),
      ));

      final lyric = n.lyric;
      if (lyric != null && lyric.isNotEmpty) {
        lyrics.add(Positioned(
          left: p.dx - tokenSize / 2,
          top: p.dy + tokenSize / 2 + 2,
          child: IgnorePointer(
            child: Text(lyric, style: lyricStyle, textAlign: TextAlign.left),
          ),
        ));
      }
    }
    // Render lyrics after tokens so they appear above any token edge.
    return [...tokens, ...lyrics];
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
