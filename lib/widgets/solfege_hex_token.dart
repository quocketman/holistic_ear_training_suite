import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/tone_token_colors.dart';

/// Hexagonal token rendered from a raw solfège label and chromatic offset,
/// independent of [MusicalState]. Used in the sequence canvas where the
/// user's typed syllable is shown verbatim.
///
/// Flat-top hex with black fill, solfège-colored outline, white Source Sans 3
/// text. Optionally tappable: when [onTapDown]/[onTapUp] are provided, the
/// token scales up while pressed.
class SolfegeHexToken extends StatefulWidget {
  final String label;
  final int chromaticOffset;
  final double size;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;

  const SolfegeHexToken({
    super.key,
    required this.label,
    required this.chromaticOffset,
    this.size = 80.0,
    this.onTapDown,
    this.onTapUp,
  });

  @override
  State<SolfegeHexToken> createState() => _SolfegeHexTokenState();
}

class _SolfegeHexTokenState extends State<SolfegeHexToken>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown() {
    _controller.forward();
    widget.onTapDown?.call();
  }

  void _handleTapUp() {
    _controller.reverse();
    widget.onTapUp?.call();
  }

  @override
  Widget build(BuildContext context) {
    final hexColor = ToneTokenColors.getColor(widget.chromaticOffset);

    final hex = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Black fill.
          SvgPicture.asset(
            'assets/hexagons/hex_00.svg',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          ),
          // Colored outline.
          SvgPicture.asset(
            'assets/hexagons/hex_outline_thick.svg',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(hexColor, BlendMode.srcIn),
          ),
          // White text.
          Text(
            widget.label,
            style: GoogleFonts.sourceSans3(
              fontSize: widget.size * 0.3,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
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
