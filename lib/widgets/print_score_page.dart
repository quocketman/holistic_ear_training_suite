import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/whiteboard_print_layout.dart';
import 'solfege_hex_token.dart';

/// Renders a single printable page of the score at the fixed print size.
///
/// White page; tokens are drawn in the "dark" token style (black fill, pitch-
/// colored ring, white label) so they read as solid discs on paper; lyrics are
/// black. The clickable link footer is added by the PDF layer, not here.
class PrintScorePage extends StatelessWidget {
  final PrintMetrics metrics;
  final PrintPage page;
  final int pageIndex;
  final String? title;

  /// Token outline shape — circle for the print sheet (matches the model).
  final SolfegeTokenShape shape;

  const PrintScorePage({
    super.key,
    required this.metrics,
    required this.page,
    required this.pageIndex,
    this.title,
    this.shape = SolfegeTokenShape.circle,
  });

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    const black = Color(0xFF000000);
    final lyricStyle = m.lyricStyle(black);
    final children = <Widget>[];

    // Centered title band on the first page only.
    if (pageIndex == 0 && title != null && title!.trim().isNotEmpty) {
      children.add(Positioned(
        top: m.margin,
        left: m.margin,
        right: m.margin,
        child: Text(
          title!.trim(),
          textAlign: TextAlign.center,
          style: GoogleFonts.sourceSans3(
            fontSize: m.tokenSize * 0.9,
            fontWeight: FontWeight.bold,
            color: black,
          ),
        ),
      ));
    }

    // Grey separator line centered in the gap between adjacent systems.
    for (var s = 0; s < page.systems.length - 1; s++) {
      final bottomOfS = page.systemTops[s] + page.systems[s].height(m);
      final yMid = bottomOfS + m.systemGap / 2;
      children.add(Positioned(
        left: m.margin,
        right: m.margin,
        top: yMid - m.systemLineThickness / 2,
        height: m.systemLineThickness,
        child: Container(color: m.systemLineColor),
      ));
    }

    for (var s = 0; s < page.systems.length; s++) {
      final sys = page.systems[s];
      final systemTop = page.systemTops[s];
      final tokensTop = systemTop + (sys.hasLyricOnly ? m.lyricLineHeight : 0);

      for (var i = 0; i < sys.notes.length; i++) {
        final n = sys.notes[i];
        if (n.isSpacer || n.isLineBreak) continue;
        final xCenter = m.margin + sys.xOffsets[i];

        if (!n.isLyricOnly) {
          final yCenter = tokensTop +
              m.tokenSize / 2 +
              (sys.maxChromatic - n.totalChromatic) * m.chromaticUnit;
          children.add(Positioned(
            left: xCenter - m.tokenSize / 2,
            top: yCenter - m.tokenSize / 2,
            width: m.tokenSize,
            height: m.tokenSize,
            child: SolfegeHexToken(
              label: n.syllable,
              chromaticOffset: n.chromaticOffset,
              size: m.tokenSize,
              state: SolfegeHexState.dark,
              theme: SolfegeHexTheme.dark, // black fill + white label
              shape: shape,
            ),
          ));
          final lyric = n.lyric;
          if (lyric != null && lyric.isNotEmpty) {
            children.add(Positioned(
              left: xCenter,
              top: yCenter + m.tokenSize / 2 + 2,
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: Text(lyric, style: lyricStyle),
              ),
            ));
          }
        } else {
          final lyric = n.lyric;
          if (lyric != null && lyric.isNotEmpty) {
            // Lyric-only words ride a row just above the tokens.
            children.add(Positioned(
              left: xCenter,
              top: systemTop + m.lyricLineHeight / 2,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: Text(lyric, style: lyricStyle),
              ),
            ));
          }
        }
      }
    }

    return Container(
      width: m.pageWidth,
      height: m.pageHeight,
      color: Colors.white,
      child: Stack(children: children),
    );
  }
}
