import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/solfege_parser.dart';
import 'solfege_hex_token.dart';

enum CanvasLayout {
  horizontal, // 1920×1080: time → x, pitch → y (higher = up)
  vertical,   // 1080×1920: time → y, pitch → x (higher = right)
}

enum CanvasJustify { left, center, right }

/// Ratio of token diameter to chromatic-semitone spacing on the pitch axis.
/// - 1.0 = tokens just touch at adjacent chromatics (whole-step gap = 1 token
///   diameter of empty space, looks puffy at wide ranges)
/// - 1.5 = tokens overlap 33% at chromatic half-steps, whole-step gap shrinks
///   to ~33% of a token diameter
/// - 2.0 = whole-step tokens just touch, half-steps overlap 50%
/// Increase for tighter visuals at wide pitch ranges.
const double _chromaticSpread = 1.5;

/// Multi-row "system band" between adjacent rows. The band is empty space
/// reserved between rows in multi-row exports; the visible separator bar
/// paints in the middle slice. All factors are in units of token size, so
/// the band scales with how big the tokens land.
const double _systemBarThicknessFactor = 0.5;
const double _systemBarPadFactor = 1.0; // padding above AND below the bar
const double _systemBandFactor =
    _systemBarThicknessFactor + 2 * _systemBarPadFactor;

/// On-screen (preview) token sizing treats the pitch axis as always at least
/// this many semitones tall. Effect: every melody whose range fits within
/// this window renders at ONE stable token size, instead of the token
/// zooming in/out each time a note widens or narrows the range. An octave
/// (12) matches the comfortable baseline; melodies wider than the window
/// still shrink to fit. Export sizing is unaffected — it uses the real range.
const double _standardPreviewPitchWindow = 12;

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

class WhiteboardCanvas extends StatefulWidget {
  final List<SolfegeNote> notes;
  final CanvasLayout layout;
  final double tokenSize;
  final String? title;
  final CanvasJustify justify;

  /// When provided, the canvas renders at this size instead of the fixed
  /// layout pixel dimensions. Used for the live on-screen preview.
  final Size? fitToSize;

  /// Optional callbacks — when provided, tokens become interactive:
  /// tap to play (and release on lift) and drag-to-play across tokens
  /// (release on rolling off, attack on rolling onto a new tile).
  final void Function(int index)? onNoteDown;
  final void Function(int index)? onNoteUp;

  /// Index of the note currently sounding via the arrow-key play loop
  /// (-1 / null = nothing playing). The matching token renders with the
  /// GLOW state so viewers see the playhead advance.
  final int? playingIndex;

  /// Dark = black bg, white text. Light = white bg, black text. Tokens
  /// invert their dark/glow fill accordingly.
  final SolfegeHexTheme theme;

  /// Outline shape of the tokens — hexagon (default) or circle.
  final SolfegeTokenShape shape;

  /// When true, the standalone `||` token splits notes into stacked rows
  /// (sheet-music style). When false (default), line-break markers render
  /// as nothing and the layout stays single-row — the right behavior for
  /// the live horizontal-scroll editor.
  final bool respectLineBreaks;

  /// Overrides [CanvasLayout.exportSize] for the off-screen render — used
  /// to retarget exports to a non-16:9 page (e.g. letter aspect for PDF
  /// print). Includes title-area height; doesn't enter preview mode, so
  /// the export 80 px margins are preserved.
  final Size? sizeOverride;

  const WhiteboardCanvas({
    super.key,
    required this.notes,
    required this.layout,
    this.tokenSize = 80.0,
    this.fitToSize,
    this.title,
    this.justify = CanvasJustify.left,
    this.onNoteDown,
    this.onNoteUp,
    this.playingIndex,
    this.theme = SolfegeHexTheme.dark,
    this.shape = SolfegeTokenShape.hex,
    this.respectLineBreaks = false,
    this.sizeOverride,
  });

  @override
  State<WhiteboardCanvas> createState() => WhiteboardCanvasState();
}

class WhiteboardCanvasState extends State<WhiteboardCanvas> {
  /// Cached center position of the token at [index] in canvas-local
  /// coordinates, or null if the canvas hasn't laid out yet or the index
  /// is out of range. Used by the screen to auto-scroll the horizontal
  /// viewport so the arrow-play playhead stays visible.
  Offset? tokenPosition(int index) {
    if (index < 0 || index >= _lastPositions.length) return null;
    return _lastPositions[index];
  }

  /// Breathing room between adjacent lyric labels, as a fraction of token
  /// size. A flat few pixels reads as crowded once tokens grow large — at
  /// that scale two words land only a hair apart ("onetime") even though
  /// they technically don't overlap. Scaling with the token keeps the gap
  /// looking consistent across zoom levels.
  static const double _lyricGapFactor = 0.35;

  /// Index of the token currently under the active pointer (-1 = none).
  int _activeIndex = -1;

  /// Whether a pointer is currently down (only attack notes while down).
  bool _pointerDown = false;

  /// Cached layout from last build for hit-testing pointer events.
  List<Offset> _lastPositions = const [];
  double _lastTokenSize = 0;

  bool get _interactive =>
      widget.onNoteDown != null || widget.onNoteUp != null;

  /// For each note in [widget.notes], returns its row index. Notes that are
  /// line-break markers themselves get row -1. In single-row mode (the
  /// default), every renderable note maps to row 0.
  ///
  /// Returned record: (rowCount, rowOfIndex, notesPerRow).
  ({int rowCount, List<int> rowOfIndex, List<int> notesPerRow})
      _rowAssignments() {
    final rowOfIndex = List<int>.filled(widget.notes.length, 0);
    final notesPerRow = <int>[];
    if (!widget.respectLineBreaks) {
      // Everyone is in row 0; spacers and lyric-only count for layout, line
      // breaks are dropped from the count.
      var count = 0;
      for (final n in widget.notes) {
        if (!n.isLineBreak) count++;
      }
      notesPerRow.add(count);
      for (var i = 0; i < widget.notes.length; i++) {
        rowOfIndex[i] = widget.notes[i].isLineBreak ? -1 : 0;
      }
      return (rowCount: 1, rowOfIndex: rowOfIndex, notesPerRow: notesPerRow);
    }
    int currentRow = 0;
    int currentCount = 0;
    for (var i = 0; i < widget.notes.length; i++) {
      final n = widget.notes[i];
      if (n.isLineBreak) {
        notesPerRow.add(currentCount);
        currentRow++;
        currentCount = 0;
        rowOfIndex[i] = -1;
        continue;
      }
      rowOfIndex[i] = currentRow;
      currentCount++;
    }
    notesPerRow.add(currentCount);
    return (
      rowCount: notesPerRow.length,
      rowOfIndex: rowOfIndex,
      notesPerRow: notesPerRow,
    );
  }

  /// Find the token index under [localPos], or -1 if none. Skips spacers
  /// and line-break markers.
  int _hitTest(Offset localPos) {
    if (_lastPositions.isEmpty || _lastTokenSize == 0) return -1;
    final r = _lastTokenSize / 2 * 0.95;
    final r2 = r * r;
    for (var i = 0; i < widget.notes.length && i < _lastPositions.length; i++) {
      if (widget.notes[i].isSpacer || widget.notes[i].isLineBreak) continue;
      final c = _lastPositions[i];
      final dx = localPos.dx - c.dx;
      final dy = localPos.dy - c.dy;
      if (dx * dx + dy * dy < r2) return i;
    }
    return -1;
  }

  void _setActive(int newIndex) {
    if (newIndex == _activeIndex) return;
    if (_activeIndex >= 0) {
      widget.onNoteUp?.call(_activeIndex);
    }
    if (newIndex >= 0 && _pointerDown) {
      widget.onNoteDown?.call(newIndex);
    }
    setState(() => _activeIndex = newIndex);
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointerDown = true;
    final hit = _hitTest(e.localPosition);
    if (hit >= 0) {
      widget.onNoteDown?.call(hit);
      setState(() => _activeIndex = hit);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointerDown) return;
    final hit = _hitTest(e.localPosition);
    _setActive(hit);
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointerDown = false;
    if (_activeIndex >= 0) {
      widget.onNoteUp?.call(_activeIndex);
    }
    setState(() => _activeIndex = -1);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointerDown = false;
    if (_activeIndex >= 0) {
      widget.onNoteUp?.call(_activeIndex);
    }
    setState(() => _activeIndex = -1);
  }

  @override
  Widget build(BuildContext context) {
    final viewport = widget.fitToSize ??
        widget.sizeOverride ??
        widget.layout.exportSize;
    final isPreview = widget.fitToSize != null;
    final titleFontSize = isPreview ? 20.0 : 48.0;
    final titleAreaHeight = isPreview ? 30.0 : widget.layout.titleHeight;
    final hasTitle = widget.title != null && widget.title!.isNotEmpty;
    final isLightTheme = widget.theme == SolfegeHexTheme.light;
    final bgColor = isLightTheme ? Colors.white : Colors.black;
    final fgColor = isLightTheme ? Colors.black : Colors.white;

    // In preview mode the canvas can extend beyond the viewport rightward —
    // the parent SingleChildScrollView handles horizontal panning. Take the
    // larger of (viewport width, natural content width) so when content fits,
    // justify and centering still work; when it overflows, we grow naturally.
    final Size size;
    if (isPreview) {
      final ts = _effectiveTokenSize(viewport, hasTitle ? titleAreaHeight : 0);
      final lyricStyle = GoogleFonts.sourceSans3(
        fontSize: ts * 0.45,
        fontWeight: FontWeight.w500,
        color: fgColor,
        height: 1.0,
      );
      final natural = _naturalContentWidth(ts, lyricStyle, true);
      size = Size(math.max(viewport.width, natural), viewport.height);
    } else {
      size = viewport;
    }

    final canvas = Container(
      width: size.width,
      height: size.height,
      color: bgColor,
      child: Stack(
        children: [
          if (hasTitle)
            Positioned(
              top: isPreview ? 4 : 20,
              left: 0,
              right: 0,
              child: Text(
                widget.title!,
                textAlign: TextAlign.center,
                style: GoogleFonts.sourceSans3(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: fgColor,
                ),
              ),
            ),
          ..._buildContent(size, hasTitle ? titleAreaHeight : 0, isLightTheme),
        ],
      ),
    );

    if (!_interactive) return canvas;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: canvas,
    );
  }

  /// Build tokens and lyrics, layered correctly.
  /// Caches positions and token size for pointer hit-testing.
  List<Widget> _buildContent(Size canvas, double titleOffset, bool isLightTheme) {
    if (widget.notes.isEmpty) {
      _lastPositions = const [];
      _lastTokenSize = 0;
      return const [];
    }

    final isPreview = widget.fitToSize != null;
    final ts = _effectiveTokenSize(canvas, titleOffset);
    final fgColor = isLightTheme ? Colors.black : Colors.white;
    final lyricStyle = GoogleFonts.sourceSans3(
      fontSize: ts * 0.45,
      fontWeight: FontWeight.w500,
      color: fgColor,
      height: 1.0,
    );
    final positions =
        _computePositions(canvas, ts, titleOffset, lyricStyle, isPreview);

    // Cache for hit-testing.
    _lastPositions = positions;
    _lastTokenSize = ts;

    final tokens = <Widget>[];
    final lyrics = <Widget>[];
    final isVertical = widget.layout == CanvasLayout.vertical;

    // System separators — bars between rows in multi-row exports. The
    // band reserved between rows is ts × _systemBandFactor; the visible
    // bar paints in the middle ts × _systemBarThicknessFactor slice.
    // Skipped in single-row mode and in vertical layout (the notion of
    // "system" is a horizontal-music convention).
    final systemBars = <Widget>[];
    final rows = _rowAssignments();
    if (widget.respectLineBreaks && rows.rowCount > 1 && !isVertical) {
      final margin = isPreview ? 20.0 : 80.0;
      final fullAxisLength = canvas.height - titleOffset - margin * 2;
      final bandHeight = ts * _systemBandFactor;
      final rowHeight =
          (fullAxisLength - (rows.rowCount - 1) * bandHeight) / rows.rowCount;
      final barHeight = ts * _systemBarThicknessFactor;
      final barColor = isLightTheme
          ? Colors.black.withValues(alpha: 0.35)
          : Colors.white.withValues(alpha: 0.35);
      // Bar between row r (above) and row r+1 (below), centered in the band.
      for (var r = 0; r < rows.rowCount - 1; r++) {
        final bandTop =
            titleOffset + margin + r * (rowHeight + bandHeight) + rowHeight;
        final yMid = bandTop + bandHeight / 2;
        systemBars.add(Positioned(
          left: margin,
          right: margin,
          top: yMid - barHeight / 2,
          height: barHeight,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(barHeight / 2),
              ),
            ),
          ),
        ));
      }
    }

    // Compute bounding rect for each group (covers tile centers, expanded
    // by half a token to enclose them, plus a little extra padding).
    final groupRects = <int, Rect>{};
    for (var i = 0; i < widget.notes.length; i++) {
      final gid = widget.notes[i].groupId;
      if (gid == null) continue;
      if (widget.notes[i].isSpacer || widget.notes[i].isLineBreak) continue;
      final p = positions[i];
      final tileRect = Rect.fromCenter(center: p, width: ts, height: ts);
      groupRects[gid] = groupRects.containsKey(gid)
          ? groupRects[gid]!.expandToInclude(tileRect)
          : tileRect;
    }
    final groupBackgrounds = <Widget>[];
    // Snug fit: a small pad, and corners rounded concentric with the token
    // outline — the box rounds at the token's radius (ts/2) plus the pad, so
    // its corners hug the edge tokens with the same curvature instead of
    // bulging into boxy corner gaps. Clamped to half the shorter side so it
    // never over-rounds on a thin group.
    final padding = ts * 0.12;
    final groupTint = isLightTheme
        ? Colors.black.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.2);
    for (final rect in groupRects.values) {
      final padded = rect.inflate(padding);
      final radius = math.min(
        ts / 2 + padding,
        math.min(padded.width, padded.height) / 2,
      );
      groupBackgrounds.add(Positioned(
        left: padded.left,
        top: padded.top,
        width: padded.width,
        height: padded.height,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: groupTint,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        ),
      ));
    }

    for (var i = 0; i < widget.notes.length; i++) {
      final n = widget.notes[i];
      if (n.isSpacer || n.isLineBreak) continue;
      final p = positions[i];
      final isActive = _interactive && i == _activeIndex;

      // Pitched notes get a hex token; lyric-only notes render just their
      // lyric text at the same anchor.
      if (!n.isLyricOnly) {
        // Glow when this is the arrow-play playhead, OR while a finger is
        // touching/dragging this token. Both surfaces share a single state.
        final isGlowing = widget.playingIndex == i ||
            (_interactive && i == _activeIndex);
        Widget tokenContent = SolfegeHexToken(
          label: n.syllable,
          chromaticOffset: n.chromaticOffset,
          size: ts,
          state: isGlowing ? SolfegeHexState.glow : SolfegeHexState.dark,
          theme: widget.theme,
          shape: widget.shape,
        );
        // In vertical mode, rotate the tile 90° clockwise so the hex shape
        // and label rotate together with the layout.
        if (isVertical) {
          tokenContent =
              RotatedBox(quarterTurns: 1, child: tokenContent);
        }

        tokens.add(Positioned(
          left: p.dx - ts / 2,
          top: p.dy - ts / 2,
          width: ts,
          height: ts,
          child: IgnorePointer(
            // Tokens should not consume pointer events when interactive —
            // the canvas-level Listener handles everything.
            ignoring: _interactive,
            child: AnimatedScale(
              scale: isActive ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: tokenContent,
            ),
          ),
        ));
      }

      final lyric = n.lyric;
      if (lyric != null && lyric.isNotEmpty) {
        // Scale the lyric up when this lyric-only note is the arrow-play
        // playhead OR when the user is currently tapping it. Mirrors the
        // GLOW / scale-up cue used for pitched tokens, so a tap on a word
        // that has no solfège still feels like an acknowledged interaction
        // (no tone — that's intentional silence).
        final isLyricActive = n.isLyricOnly &&
            (widget.playingIndex == i ||
                (_interactive && i == _activeIndex));
        Widget lyricWidget = Text(
          lyric,
          style: isLyricActive
              ? lyricStyle.copyWith(
                  fontSize: (lyricStyle.fontSize ?? 16) * 1.8,
                  fontWeight: FontWeight.w700,
                )
              : lyricStyle,
          textAlign: TextAlign.left,
        );
        if (isVertical) {
          // Rotate lyric 90° clockwise to match rotated tiles. Position it
          // to the right of the tile (or centered on p for lyric-only).
          lyrics.add(Positioned(
            left: n.isLyricOnly ? p.dx : p.dx + ts / 2 + 2,
            top: p.dy - ts / 2,
            child: FractionalTranslation(
              translation: n.isLyricOnly
                  ? const Offset(-0.5, 0)
                  : Offset.zero,
              child: IgnorePointer(
                child: RotatedBox(quarterTurns: 1, child: lyricWidget),
              ),
            ),
          ));
        } else {
          // Pitched: lyric sits below the hex. Lyric-only: centered on the
          // anchor point in both axes.
          lyrics.add(Positioned(
            left: p.dx,
            top: n.isLyricOnly ? p.dy : p.dy + ts / 2 + 2,
            child: FractionalTranslation(
              translation: Offset(-0.5, n.isLyricOnly ? -0.5 : 0),
              child: IgnorePointer(child: lyricWidget),
            ),
          ));
        }
      }
    }
    // System separators sit lowest, then group backgrounds (behind tokens),
    // then tokens, then lyrics on top.
    return [...systemBars, ...groupBackgrounds, ...tokens, ...lyrics];
  }

  /// Compute effective token size that fits everything in the content area.
  double _effectiveTokenSize(Size canvas, double titleOffset) {
    if (widget.notes.isEmpty) return widget.tokenSize;

    final realChromatics = [
      for (var i = 0; i < widget.notes.length; i++)
        if (!widget.notes[i].isSpacer &&
            !widget.notes[i].isLyricOnly &&
            !widget.notes[i].isLineBreak)
          widget.notes[i].totalChromatic,
    ];
    if (realChromatics.isEmpty) return widget.tokenSize;

    final minC = realChromatics.reduce((a, b) => a < b ? a : b);
    final maxC = realChromatics.reduce((a, b) => a > b ? a : b);
    final pitchRange = maxC - minC;

    final isPreview = widget.fitToSize != null;
    final margin = isPreview ? 20.0 : 80.0;

    final rows = _rowAssignments();
    final rowCount = rows.rowCount;
    final maxNotesPerRow = rows.notesPerRow.isEmpty
        ? widget.notes.length
        : rows.notesPerRow.reduce(math.max);

    final timeAxisLength = (widget.layout == CanvasLayout.horizontal
            ? canvas.width
            : canvas.height - titleOffset) -
        margin * 2;
    // Full pitch axis (across all rows). In single-row mode it's the entire
    // music area; in multi-row, rows + inter-row bands all share this.
    final fullPitchAxisLength = (widget.layout == CanvasLayout.horizontal
            ? canvas.height - titleOffset
            : canvas.width) -
        margin * 2;

    // In preview mode, the canvas can grow rightward inside a
    // SingleChildScrollView, so don't shrink tokens to fit the time axis.
    // In export mode (fixed-size PNG), keep the constraint.
    final maxFromTime = isPreview
        ? double.infinity
        : maxNotesPerRow > 0
            ? timeAxisLength / maxNotesPerRow
            : widget.tokenSize;
    // In horizontal mode, lyrics render below each hex (font = ts × 0.45 +
    // 2 px gap). When the pitch span is wide, the bottom token's lyric
    // would otherwise clip past canvas.height — reserve a fraction of a
    // token below the lowest tile so the lyric line stays inside.
    final bool reserveLyricBelow = widget.layout == CanvasLayout.horizontal &&
        widget.notes.any((n) =>
            !n.isLineBreak && n.lyric != null && n.lyric!.isNotEmpty);
    const double lyricReserveFactor = 0.7;
    // Multi-row horizontal exports reserve a system band between rows.
    // bandHeight = ts × _systemBandFactor; the joint pitch-axis constraint is:
    //   rowCount × (pitchRange × ts/spread + ts × (1+R))
    //     + (rowCount-1) × ts × _systemBandFactor
    //   = fullPitchAxisLength
    // → ts × [rowCount × (pitchRange + spread × (1+R))
    //         + spread × (rowCount-1) × _systemBandFactor]
    //   = fullPitchAxisLength × spread
    final bool reserveBands = widget.respectLineBreaks &&
        rowCount > 1 &&
        widget.layout == CanvasLayout.horizontal;
    // On-screen: hold the token size stable by sizing as if the pitch axis is
    // always at least one octave tall, so notes within an octave don't rescale
    // the board. Export keeps the true range so it packs tightly.
    final double effectivePitchRange = isPreview
        ? math.max(pitchRange.toDouble(), _standardPreviewPitchWindow)
        : pitchRange.toDouble();
    final double pitchDenom = rowCount *
            (effectivePitchRange +
                _chromaticSpread *
                    (1 + (reserveLyricBelow ? lyricReserveFactor : 0))) +
        _chromaticSpread *
            (reserveBands ? (rowCount - 1) * _systemBandFactor : 0);
    final maxFromPitch =
        effectivePitchRange > 0 || reserveLyricBelow || reserveBands
            ? fullPitchAxisLength * _chromaticSpread / pitchDenom
            : fullPitchAxisLength;

    return [widget.tokenSize, maxFromTime, maxFromPitch]
        .reduce((a, b) => a < b ? a : b);
  }

  /// For each non-pitched note (lyric-only or spacer), linearly interpolate
  /// a chromatic value from the nearest pitched neighbours on either side.
  /// This places lyric-only notes vertically between their flanking pitched
  /// notes; if only one side has a pitched note we clamp to that value.
  List<int> _interpolateChromatics({
    required List<int> rawChromatics,
    required List<int> pitchedIndices,
  }) {
    final result = List<int>.from(rawChromatics);
    final pitchedSet = pitchedIndices.toSet();
    for (var i = 0; i < rawChromatics.length; i++) {
      if (pitchedSet.contains(i)) continue;

      int? prevIdx;
      for (var j = i - 1; j >= 0; j--) {
        if (pitchedSet.contains(j)) {
          prevIdx = j;
          break;
        }
      }
      int? nextIdx;
      for (var j = i + 1; j < rawChromatics.length; j++) {
        if (pitchedSet.contains(j)) {
          nextIdx = j;
          break;
        }
      }

      if (prevIdx != null && nextIdx != null) {
        final pc = rawChromatics[prevIdx];
        final nc = rawChromatics[nextIdx];
        final fraction = (i - prevIdx) / (nextIdx - prevIdx);
        result[i] = (pc + (nc - pc) * fraction).round();
      } else if (prevIdx != null) {
        result[i] = rawChromatics[prevIdx];
      } else if (nextIdx != null) {
        result[i] = rawChromatics[nextIdx];
      }
      // Both-null case is impossible: caller ensures pitchedIndices is non-empty.
    }
    return result;
  }

  /// Natural width of the content (margins + first/last half-token + the sum
  /// of all time-step gaps). Used in preview mode to size the canvas so it
  /// can extend rightward inside a SingleChildScrollView.
  double _naturalContentWidth(double ts, TextStyle lyricStyle, bool isPreview) {
    if (widget.notes.isEmpty) return 0;
    final margin = isPreview ? 20.0 : 80.0;
    double sumSteps = 0;
    for (var i = 1; i < widget.notes.length; i++) {
      final cur = widget.notes[i];
      final prev = widget.notes[i - 1];
      // Line-break markers and the steps into/out of them take no horizontal
      // space in single-row mode — they're collapsed to zero width.
      if (cur.isLineBreak || prev.isLineBreak) continue;
      sumSteps += _horizontalStep(prev, cur, ts, lyricStyle);
    }
    return 2 * margin + ts + sumSteps;
  }

  /// Horizontal advance between two consecutive renderable notes on the time
  /// axis. At minimum one token diameter so the hexes never collide. Because
  /// each lyric is drawn centered under its own token, two adjacent lyrics
  /// overlap once the gap drops below half of each one's width plus the
  /// breathing gap — so widen the step by `(prevWidth + curWidth) / 2 + gap`
  /// whenever either note carries a lyric. (Considering only the previous
  /// lyric, as the old code did, let a short word crowd into a long one that
  /// followed it.) Vertical layout rotates lyrics to the side, so its step is
  /// always a plain token diameter.
  double _horizontalStep(
      SolfegeNote prev, SolfegeNote cur, double ts, TextStyle style) {
    if (widget.layout != CanvasLayout.horizontal) return ts;
    final prevW = (prev.lyric != null && prev.lyric!.isNotEmpty)
        ? _measureLyricWidth(prev.lyric!, style)
        : 0.0;
    final curW = (cur.lyric != null && cur.lyric!.isNotEmpty)
        ? _measureLyricWidth(cur.lyric!, style)
        : 0.0;
    if (prevW == 0 && curW == 0) return ts;
    return math.max(ts, (prevW + curW) / 2 + ts * _lyricGapFactor);
  }

  double _measureLyricWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  List<Offset> _computePositions(
    Size canvas,
    double ts,
    double titleOffset,
    TextStyle lyricStyle,
    bool isPreview,
  ) {
    final rawChromatics = widget.notes.map((n) => n.totalChromatic).toList();
    final pitchedIndices = <int>[
      for (var i = 0; i < widget.notes.length; i++)
        if (!widget.notes[i].isSpacer &&
            !widget.notes[i].isLyricOnly &&
            !widget.notes[i].isLineBreak)
          i,
    ];

    final int minC;
    final int maxC;
    final List<int> chromatics;
    if (pitchedIndices.isEmpty) {
      // No pitch info anywhere — collapse every note to the same chromatic
      // value so they all land at the canvas's vertical centerline.
      minC = 0;
      maxC = 0;
      chromatics = List.filled(widget.notes.length, 0);
    } else {
      final pitched = pitchedIndices.map((i) => rawChromatics[i]).toList();
      minC = pitched.reduce((a, b) => a < b ? a : b);
      maxC = pitched.reduce((a, b) => a > b ? a : b);
      chromatics = _interpolateChromatics(
        rawChromatics: rawChromatics,
        pitchedIndices: pitchedIndices,
      );
    }

    // Chromatic positioning is decoupled from token size: each semitone
    // steps by ts / _chromaticSpread, so adjacent semitones overlap by
    // the spread factor at render time.
    final chromaticUnit = ts / _chromaticSpread;
    final pitchSpan = (maxC - minC) * chromaticUnit;

    final margin = isPreview ? 20.0 : 80.0;
    final rows = _rowAssignments();
    final rowCount = rows.rowCount;
    final rowOfIndex = rows.rowOfIndex;

    // Per-row pitch axis: the music area minus inter-row system bands,
    // divided evenly across rows. In single-row mode this collapses back
    // to the full music area.
    final fullPitchAxisLength = (widget.layout == CanvasLayout.horizontal
            ? canvas.height - titleOffset
            : canvas.width) -
        margin * 2;
    final bool useBands = widget.respectLineBreaks &&
        rowCount > 1 &&
        widget.layout == CanvasLayout.horizontal;
    final double bandHeight = useBands ? ts * _systemBandFactor : 0.0;
    final rowHeight =
        (fullPitchAxisLength - (rowCount - 1) * bandHeight) / rowCount;
    final timeAxisLength = (widget.layout == CanvasLayout.horizontal
            ? canvas.width
            : canvas.height - titleOffset) -
        margin * 2;

    // Per-row time offsets — each row starts at 0 and accumulates by ts (or
    // wider lyric step) only on transitions between renderable notes in the
    // same row. Line breaks belong to row -1 and contribute nothing.
    final timeOffsetForIndex = List<double>.filled(widget.notes.length, 0.0);
    final rowLastRenderable = List<int?>.filled(rowCount, null);
    for (var i = 0; i < widget.notes.length; i++) {
      final r = rowOfIndex[i];
      if (r < 0) continue;
      final prevIdx = rowLastRenderable[r];
      if (prevIdx == null) {
        timeOffsetForIndex[i] = 0.0;
      } else {
        final prev = widget.notes[prevIdx];
        final step = _horizontalStep(prev, widget.notes[i], ts, lyricStyle);
        timeOffsetForIndex[i] = timeOffsetForIndex[prevIdx] + step;
      }
      rowLastRenderable[r] = i;
    }
    final perRowTimeSpan = List<double>.generate(rowCount, (r) {
      final last = rowLastRenderable[r];
      return last == null ? 0.0 : timeOffsetForIndex[last];
    });

    // Per-row time start (justify within each row independently).
    final perRowTimeStart = List<double>.generate(rowCount, (r) {
      switch (widget.justify) {
        case CanvasJustify.left:
          return margin + ts / 2;
        case CanvasJustify.center:
          return margin + (timeAxisLength - perRowTimeSpan[r]) / 2;
        case CanvasJustify.right:
          return margin + timeAxisLength - perRowTimeSpan[r] - ts / 2;
      }
    });

    // Per-row pitch baseline — lowest-pitch's center coordinate on the
    // pitch axis, derived from the row's vertical range plus a centering
    // pad. Each step between rows includes one bandHeight of system-bar
    // reservation. In single-row mode this collapses to the original
    // pitchStart formula.
    final perRowPitchAxisStart = List<double>.generate(rowCount, (r) {
      // r=0 is the top row, r=rowCount-1 is the bottom row.
      final padInRow = (rowHeight - pitchSpan) / 2;
      return margin +
          (rowCount - 1 - r) * (rowHeight + bandHeight) +
          padInRow;
    });

    // Lyric-only words have no pitch. Rather than interpolate a height from
    // their pitched neighbours (which made them bob up and down with the
    // melody), park them all at one uniform height along the TOP of their
    // row band — just under the text input — so they read as a lyric line
    // above the music. Inset a little so the words don't clip the top edge.
    final lyricOnlyInset = ts * 0.4;
    double bandStartFor(int r) =>
        margin + (rowCount - 1 - r) * (rowHeight + bandHeight);

    return List.generate(widget.notes.length, (i) {
      final r = rowOfIndex[i];
      // Line-break markers have no on-screen presence; park them at origin.
      if (r < 0) return Offset.zero;

      final timePos = perRowTimeStart[r] + timeOffsetForIndex[i];

      if (widget.notes[i].isLyricOnly) {
        switch (widget.layout) {
          case CanvasLayout.horizontal:
            // Pitch axis runs bottom→top; the band top is the high end.
            final rowTopY = canvas.height - bandStartFor(r) - rowHeight;
            return Offset(timePos, rowTopY + lyricOnlyInset);
          case CanvasLayout.vertical:
            // Pitch axis runs left→right (higher = right); park at the
            // high-pitch (right) edge for a uniform column.
            final rowRightX = bandStartFor(r) + rowHeight - lyricOnlyInset;
            return Offset(rowRightX, titleOffset + timePos);
        }
      }

      final pitchOffsetFromMin = (chromatics[i] - minC) * chromaticUnit;
      final rowPitchStart = perRowPitchAxisStart[r];

      switch (widget.layout) {
        case CanvasLayout.horizontal:
          final y = canvas.height - rowPitchStart - pitchOffsetFromMin;
          return Offset(timePos, y);
        case CanvasLayout.vertical:
          final x = rowPitchStart + pitchOffsetFromMin;
          return Offset(x, titleOffset + timePos);
      }
    });
  }
}
