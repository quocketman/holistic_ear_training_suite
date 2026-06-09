import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/tone_token_colors.dart';

/// Visual state of a solfège hex token. Mirrors the Illustrator-exported
/// asset states in `Hex Graphic Assets/` (see project_hex_token_assets memory).
enum SolfegeHexState {
  /// Colored fill with white outline. Bright, foreground-y.
  color,

  /// Black fill with colored outline. Default Whiteboard look — reads well
  /// on a dark scaffold.
  dark,

  /// Muted/desaturated variant for inactive or background tokens.
  grey,

  /// "This pitch is NOT in the set" indicator (e.g., fa/ti for pentatonic).
  /// Rendered as a low-opacity outline with no fill.
  no,

  /// Active / sounding state. Adds an outer glow on top of the dark base.
  glow,
}

/// Hexagonal token rendered procedurally to match the Illustrator
/// `hex_<state>_<syllable>_<octave>.svg` set without bundling SVG assets.
///
/// Flat-top hexagon (flat horizontal edges on top and bottom, points on
/// left and right). Label is whatever syllable the parent passes in —
/// the token shows it verbatim (so `di` shows `di`, `ra` shows `ra`).
class SolfegeHexToken extends StatefulWidget {
  final String label;
  final int chromaticOffset;
  final double size;
  final SolfegeHexState state;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;

  const SolfegeHexToken({
    super.key,
    required this.label,
    required this.chromaticOffset,
    this.size = 80.0,
    this.state = SolfegeHexState.dark,
    this.onTapDown,
    this.onTapUp,
  });

  @override
  State<SolfegeHexToken> createState() => _SolfegeHexTokenState();
}

class _SolfegeHexTokenState extends State<SolfegeHexToken>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown() {
    _scaleController.forward();
    widget.onTapDown?.call();
  }

  void _handleTapUp() {
    _scaleController.reverse();
    widget.onTapUp?.call();
  }

  @override
  Widget build(BuildContext context) {
    final hexColor = ToneTokenColors.getColor(widget.chromaticOffset);

    // Label opacity matches the visible token "presence" — NO tokens get a
    // faded label so the message ("this isn't in the set") reads even when
    // the hex is dim.
    final labelOpacity = widget.state == SolfegeHexState.no ? 0.45 : 1.0;

    final hex = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(widget.size),
            painter: _HexPainter(
              color: hexColor,
              state: widget.state,
            ),
          ),
          // Label fills the hex's safe interior. FittedBox scales the
          // text uniformly so 2-char syllables ("do") and 4-char compounds
          // ("dira", "lesi") both occupy the same bounding box at the
          // largest size that fits both width and height.
          Center(
            child: SizedBox(
              width: widget.size * 0.78,
              height: widget.size * 0.48,
              child: Opacity(
                opacity: labelOpacity,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    widget.label,
                    style: GoogleFonts.sourceSans3(
                      // Large base size — FittedBox scales it to fit.
                      fontSize: 100,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.onTapDown == null && widget.onTapUp == null) {
      return hex;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _handleTapDown(),
      onTapUp: (_) => _handleTapUp(),
      onTapCancel: _handleTapUp,
      child: ScaleTransition(scale: _scale, child: hex),
    );
  }
}

/// Paints a flat-top hexagon with fill, stroke, and (optional) outer glow.
/// Geometry approximates the Illustrator-exported assets at ~88% inset of
/// the bounding box.
class _HexPainter extends CustomPainter {
  final Color color;
  final SolfegeHexState state;

  const _HexPainter({
    required this.color,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _flatTopHexPath(size, inset: 0.92);

    // Outer glow drawn first so it sits behind fill + stroke.
    if (state == SolfegeHexState.glow) {
      final glowPaint = Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 18);
      canvas.drawPath(path, glowPaint);

      // A second, tighter glow gives a warmer center to the halo.
      final innerGlow = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8);
      canvas.drawPath(path, innerGlow);
    }

    // Fill
    final fillColor = switch (state) {
      SolfegeHexState.color => color,
      SolfegeHexState.dark || SolfegeHexState.glow => Colors.black,
      SolfegeHexState.grey => const Color(0xFF2A2A2A),
      SolfegeHexState.no => Colors.transparent,
    };
    if (fillColor.a > 0) {
      canvas.drawPath(path, Paint()..color = fillColor);
    }

    // Stroke. Width scales with the hex size so borders stay visually
    // balanced from 24-pixel mini-tokens up to 200-pixel canvas-fillers.
    // Clamped at 0.6px on the low end to avoid sub-pixel aliasing artifacts.
    final thickStroke = (size.width * 0.025).clamp(0.6, double.infinity);
    final thinStroke = (size.width * 0.019).clamp(0.6, double.infinity);
    final (strokeColor, strokeWidth) = switch (state) {
      SolfegeHexState.color => (Colors.white.withValues(alpha: 0.35), thinStroke),
      SolfegeHexState.dark || SolfegeHexState.glow => (color, thickStroke),
      SolfegeHexState.grey => (const Color(0xFF555555), thinStroke),
      SolfegeHexState.no => (color.withValues(alpha: 0.45), thinStroke),
    };
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  /// Flat-top hexagon path: flat edges on top and bottom, vertex points
  /// on left and right. Inset shrinks the hex within the bounding box.
  Path _flatTopHexPath(Size size, {double inset = 0.92}) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width / 2) * inset;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (60.0 * i) * math.pi / 180.0;
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HexPainter old) =>
      old.color != color || old.state != state;
}
