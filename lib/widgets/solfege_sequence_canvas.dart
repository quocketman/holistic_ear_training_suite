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

class SolfegeSequenceCanvas extends StatefulWidget {
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

  const SolfegeSequenceCanvas({
    super.key,
    required this.notes,
    required this.layout,
    this.tokenSize = 80.0,
    this.fitToSize,
    this.title,
    this.justify = CanvasJustify.left,
    this.onNoteDown,
    this.onNoteUp,
  });

  @override
  State<SolfegeSequenceCanvas> createState() => _SolfegeSequenceCanvasState();
}

class _SolfegeSequenceCanvasState extends State<SolfegeSequenceCanvas> {
  static const double _lyricGap = 4.0;

  /// Index of the token currently under the active pointer (-1 = none).
  int _activeIndex = -1;

  /// Whether a pointer is currently down (only attack notes while down).
  bool _pointerDown = false;

  /// Cached layout from last build for hit-testing pointer events.
  List<Offset> _lastPositions = const [];
  double _lastTokenSize = 0;

  bool get _interactive =>
      widget.onNoteDown != null || widget.onNoteUp != null;

  /// Find the token index under [localPos], or -1 if none. Skips spacers.
  int _hitTest(Offset localPos) {
    if (_lastPositions.isEmpty || _lastTokenSize == 0) return -1;
    final r = _lastTokenSize / 2 * 0.95;
    final r2 = r * r;
    for (var i = 0; i < widget.notes.length && i < _lastPositions.length; i++) {
      if (widget.notes[i].isSpacer) continue;
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
    final size = widget.fitToSize ?? widget.layout.exportSize;
    final isPreview = widget.fitToSize != null;
    final titleFontSize = isPreview ? 20.0 : 48.0;
    final titleAreaHeight = isPreview ? 30.0 : widget.layout.titleHeight;
    final hasTitle = widget.title != null && widget.title!.isNotEmpty;

    final canvas = Container(
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
                widget.title!,
                textAlign: TextAlign.center,
                style: GoogleFonts.sourceSans3(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ..._buildContent(size, hasTitle ? titleAreaHeight : 0),
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
  List<Widget> _buildContent(Size canvas, double titleOffset) {
    if (widget.notes.isEmpty) {
      _lastPositions = const [];
      _lastTokenSize = 0;
      return const [];
    }

    final isPreview = widget.fitToSize != null;
    final ts = _effectiveTokenSize(canvas, titleOffset);
    final lyricStyle = GoogleFonts.sourceSans3(
      fontSize: ts * 0.3,
      fontWeight: FontWeight.w500,
      color: Colors.white,
      height: 1.0,
    );
    final positions =
        _computePositions(canvas, ts, titleOffset, lyricStyle, isPreview);

    // Cache for hit-testing.
    _lastPositions = positions;
    _lastTokenSize = ts;

    final tokens = <Widget>[];
    final lyrics = <Widget>[];

    for (var i = 0; i < widget.notes.length; i++) {
      final n = widget.notes[i];
      if (n.isSpacer) continue;
      final p = positions[i];
      final isActive = _interactive && i == _activeIndex;

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
            child: SolfegeHexToken(
              label: n.syllable,
              chromaticOffset: n.chromaticOffset,
              size: ts,
            ),
          ),
        ),
      ));

      final lyric = n.lyric;
      if (lyric != null && lyric.isNotEmpty) {
        lyrics.add(Positioned(
          left: p.dx - ts / 2,
          top: p.dy + ts / 2 + 2,
          child: IgnorePointer(
            child: Text(lyric, style: lyricStyle, textAlign: TextAlign.left),
          ),
        ));
      }
    }
    // Render lyrics after tokens so they appear above any token edge.
    return [...tokens, ...lyrics];
  }

  /// Compute effective token size that fits everything in the content area.
  double _effectiveTokenSize(Size canvas, double titleOffset) {
    if (widget.notes.isEmpty) return widget.tokenSize;

    final realChromatics = [
      for (var i = 0; i < widget.notes.length; i++)
        if (!widget.notes[i].isSpacer) widget.notes[i].totalChromatic,
    ];
    if (realChromatics.isEmpty) return widget.tokenSize;

    final minC = realChromatics.reduce((a, b) => a < b ? a : b);
    final maxC = realChromatics.reduce((a, b) => a > b ? a : b);
    final pitchRange = maxC - minC;

    final isPreview = widget.fitToSize != null;
    final margin = isPreview ? 20.0 : 80.0;

    final timeAxisLength = (widget.layout == CanvasLayout.horizontal
            ? canvas.width
            : canvas.height - titleOffset) -
        margin * 2;
    final pitchAxisLength = (widget.layout == CanvasLayout.horizontal
            ? canvas.height - titleOffset
            : canvas.width) -
        margin * 2;

    final maxFromTime = widget.notes.isNotEmpty
        ? timeAxisLength / widget.notes.length
        : widget.tokenSize;
    final maxFromPitch = pitchRange > 0
        ? pitchAxisLength / (pitchRange + 1)
        : pitchAxisLength;

    return [widget.tokenSize, maxFromTime, maxFromPitch]
        .reduce((a, b) => a < b ? a : b);
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
    final chromatics = widget.notes.map((n) => n.totalChromatic).toList();
    final realChromatics = [
      for (var i = 0; i < widget.notes.length; i++)
        if (!widget.notes[i].isSpacer) chromatics[i],
    ];
    if (realChromatics.isEmpty) {
      return List.filled(widget.notes.length, Offset.zero);
    }
    final minC = realChromatics.reduce((a, b) => a < b ? a : b);
    final maxC = realChromatics.reduce((a, b) => a > b ? a : b);
    final pitchSpan = (maxC - minC) * ts;

    final margin = isPreview ? 20.0 : 80.0;

    final pitchAxisLength = (widget.layout == CanvasLayout.horizontal
            ? canvas.height - titleOffset
            : canvas.width) -
        margin * 2;
    final timeAxisLength = (widget.layout == CanvasLayout.horizontal
            ? canvas.width
            : canvas.height - titleOffset) -
        margin * 2;

    // Compute step offsets: tokens normally step by ts, but in horizontal
    // mode a wide lyric on token i pushes token i+1 right by enough to clear it.
    final timeOffsets = <double>[0.0];
    for (var i = 1; i < widget.notes.length; i++) {
      final prev = widget.notes[i - 1];
      var step = ts;
      if (widget.layout == CanvasLayout.horizontal &&
          prev.lyric != null &&
          prev.lyric!.isNotEmpty) {
        final w = _measureLyricWidth(prev.lyric!, lyricStyle);
        step = math.max(ts, w + _lyricGap);
      }
      timeOffsets.add(timeOffsets.last + step);
    }
    final timeSpan = timeOffsets.last;

    // Pitch axis: center the chromatic range within the content area.
    final pitchStart = margin + (pitchAxisLength - pitchSpan) / 2;

    // Time axis: justify left, center, or right.
    final double timeStart;
    switch (widget.justify) {
      case CanvasJustify.left:
        timeStart = margin + ts / 2;
      case CanvasJustify.center:
        timeStart = margin + (timeAxisLength - timeSpan) / 2;
      case CanvasJustify.right:
        timeStart = margin + timeAxisLength - timeSpan - ts / 2;
    }

    return List.generate(widget.notes.length, (i) {
      final timePos = timeStart + timeOffsets[i];
      final pitchOffsetFromMin = (chromatics[i] - minC) * ts;

      switch (widget.layout) {
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
