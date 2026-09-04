import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/solfege_parser.dart';

/// Fixed-size, auto-wrapping, paginated layout for the printable PDF.
///
/// Unlike the on-screen [WhiteboardCanvas] (which scales tokens to fit), the
/// print layout holds ONE fixed token size and wraps the melody into stacked
/// "systems" (lines of music) that fit the page's printable width, then packs
/// those systems onto letter pages — flowing onto more pages as needed.
///
/// All dimensions are in the export pixel space (200 dpi letter = 1700×2200),
/// so 1 inch = 200 px.
class PrintMetrics {
  final double pageWidth;
  final double pageHeight;
  final double margin; // page margin on all sides (0.75" = 150)
  final double tokenSize; // fixed token diameter (0.3" = 60)
  final double chromaticSpread; // token diameter ÷ semitone spacing
  final double systemGap; // vertical gap between stacked systems
  final double titleHeight; // reserved for the centered title on page 1
  final double footerHeight; // reserved at the bottom for the link

  const PrintMetrics({
    this.pageWidth = 1700,
    this.pageHeight = 2200,
    this.margin = 150,
    this.tokenSize = 60,
    this.chromaticSpread = 1.5,
    this.systemGap = 120, // ~two tokens of breathing room between systems
    this.titleHeight = 150,
    this.footerHeight = 64,
  });

  /// Thickness + color of the grey separator drawn midway between systems.
  double get systemLineThickness => 3;
  Color get systemLineColor => const Color(0xFFBBBBBB);

  double get chromaticUnit => tokenSize / chromaticSpread;
  double get printableWidth => pageWidth - 2 * margin;
  double get lyricFontSize => tokenSize * 0.45;
  double get lyricLineHeight => tokenSize * 0.62; // room for a lyric row
  double get lyricGap => tokenSize * 0.35;

  /// Y at which page content must stop (above the footer/link zone).
  double get contentBottom => pageHeight - margin - footerHeight;

  /// Y at which content begins on a page. Page 0 reserves the title band.
  double contentTop(int pageIndex) =>
      margin + (pageIndex == 0 ? titleHeight : 0);

  TextStyle lyricStyle(Color color) => GoogleFonts.sourceSans3(
        fontSize: lyricFontSize,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.0,
      );
}

/// One line of music: a run of notes with their computed horizontal offsets
/// (local to the system's left edge) and pitch extent.
class PrintSystem {
  final List<SolfegeNote> notes;
  final List<double> xOffsets; // center x of each note, from system left
  final int minChromatic;
  final int maxChromatic;
  final bool hasLyricOnly; // a lyric row sits ABOVE the tokens
  final bool hasPitchedLyric; // a lyric row sits BELOW the tokens

  const PrintSystem({
    required this.notes,
    required this.xOffsets,
    required this.minChromatic,
    required this.maxChromatic,
    required this.hasLyricOnly,
    required this.hasPitchedLyric,
  });

  int get pitchSpread => maxChromatic - minChromatic;

  /// Total vertical footprint of this system in the given metrics.
  double height(PrintMetrics m) =>
      pitchSpread * m.chromaticUnit +
      m.tokenSize +
      (hasLyricOnly ? m.lyricLineHeight : 0) +
      (hasPitchedLyric ? m.lyricLineHeight : 0);
}

/// A page and the vertical position of each of its systems' top edges.
class PrintPage {
  final List<PrintSystem> systems;
  final List<double> systemTops;
  const PrintPage({required this.systems, required this.systemTops});
}

/// The full paginated print job.
class PrintJob {
  final List<PrintPage> pages;
  const PrintJob(this.pages);
  int get pageCount => pages.length;
}

double _measureLyricWidth(String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}

double _step(SolfegeNote prev, SolfegeNote cur, PrintMetrics m, TextStyle s) {
  final prevW = (prev.lyric != null && prev.lyric!.isNotEmpty)
      ? _measureLyricWidth(prev.lyric!, s)
      : 0.0;
  final curW = (cur.lyric != null && cur.lyric!.isNotEmpty)
      ? _measureLyricWidth(cur.lyric!, s)
      : 0.0;
  if (prevW == 0 && curW == 0) return m.tokenSize;
  return math.max(m.tokenSize, (prevW + curW) / 2 + m.lyricGap);
}

/// Break [notes] into systems: a new system starts on a manual `[]` line
/// break OR when the next token would cross the printable-width margin.
List<PrintSystem> segmentSystems(List<SolfegeNote> notes, PrintMetrics m) {
  final style = m.lyricStyle(const Color(0xFF000000));
  final systems = <PrintSystem>[];

  var current = <SolfegeNote>[];
  var xs = <double>[];
  double cursor = 0; // center-x of the last placed note
  SolfegeNote? prev;

  void flush() {
    if (current.isEmpty) return;
    final pitched = [
      for (final n in current)
        if (!n.isSpacer && !n.isLyricOnly && !n.isLineBreak) n.totalChromatic,
    ];
    final minC = pitched.isEmpty ? 0 : pitched.reduce(math.min);
    final maxC = pitched.isEmpty ? 0 : pitched.reduce(math.max);
    systems.add(PrintSystem(
      notes: List.of(current),
      xOffsets: List.of(xs),
      minChromatic: minC,
      maxChromatic: maxC,
      hasLyricOnly: current.any((n) => n.isLyricOnly && (n.lyric?.isNotEmpty ?? false)),
      hasPitchedLyric: current.any(
          (n) => !n.isLyricOnly && !n.isLineBreak && (n.lyric?.isNotEmpty ?? false)),
    ));
    current = <SolfegeNote>[];
    xs = <double>[];
    cursor = 0;
    prev = null;
  }

  for (final n in notes) {
    if (n.isLineBreak) {
      flush();
      continue;
    }
    final double center;
    if (prev == null) {
      center = m.tokenSize / 2;
    } else {
      final next = cursor + _step(prev!, n, m, style);
      // Wrap when this token's right edge would cross the printable width.
      if (next + m.tokenSize / 2 > m.printableWidth && current.isNotEmpty) {
        flush();
        center = m.tokenSize / 2;
      } else {
        center = next;
      }
    }
    current.add(n);
    xs.add(center);
    cursor = center;
    prev = n;
  }
  flush();
  return systems;
}

/// Pack systems onto pages by height, flowing onto new pages as needed.
PrintJob paginate(List<SolfegeNote> notes, PrintMetrics m) {
  final systems = segmentSystems(notes, m);
  final pages = <PrintPage>[];

  var pageSystems = <PrintSystem>[];
  var tops = <double>[];
  var pageIndex = 0;
  double y = m.contentTop(0);

  void newPage() {
    pages.add(PrintPage(systems: List.of(pageSystems), systemTops: List.of(tops)));
    pageSystems = <PrintSystem>[];
    tops = <double>[];
    pageIndex++;
    y = m.contentTop(pageIndex);
  }

  for (final sys in systems) {
    final h = sys.height(m);
    if (pageSystems.isNotEmpty && y + h > m.contentBottom) {
      newPage();
    }
    pageSystems.add(sys);
    tops.add(y);
    y += h + m.systemGap;
  }
  if (pageSystems.isNotEmpty) {
    pages.add(PrintPage(systems: pageSystems, systemTops: tops));
  }
  // Always at least one (blank) page so callers can render something.
  if (pages.isEmpty) {
    pages.add(const PrintPage(systems: [], systemTops: []));
  }
  return PrintJob(pages);
}
