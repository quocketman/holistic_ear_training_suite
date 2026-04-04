import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../models/note_nugget.dart';
import '../models/musical_state.dart';
import '../models/enums.dart';
import '../models/tone_token_colors.dart';

/// Visual representation of a musical note using hexagonal tokens
/// Displays an SVG hexagon with a solfège text label overlay
class ToneToken extends StatefulWidget {
  final NoteNugget noteNugget;
  final double size;
  final HexagonOrientation orientation;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;
  final bool glowing;

  /// Legacy callback - triggers on tap down for backwards compatibility
  final VoidCallback? onTap;

  const ToneToken({
    super.key,
    required this.noteNugget,
    this.size = 80.0,
    this.orientation = HexagonOrientation.flatTop,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.glowing = false,
  });

  @override
  State<ToneToken> createState() => _ToneTokenState();
}

class _ToneTokenState extends State<ToneToken>
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

  @override
  void didUpdateWidget(ToneToken oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.glowing && !oldWidget.glowing) {
      _controller.forward();
    } else if (!widget.glowing && oldWidget.glowing) {
      _controller.reverse();
    }
  }

  void _handleTapDown() {
    _controller.forward();
    widget.onTapDown?.call();
    widget.onTap?.call(); // Legacy support
  }

  void _handleTapUp() {
    if (!widget.glowing) _controller.reverse();
    widget.onTapUp?.call();
  }

  @override
  Widget build(BuildContext context) {
    final musicalState = context.watch<MusicalState>();
    final solfegeLabel = musicalState.solfegeFromCurrentKey(widget.noteNugget);

    final chromaticOffset = widget.noteNugget.getChromaticOffset(musicalState.currentMode);
    final hexColor = ToneTokenColors.getColor(chromaticOffset);

    final rotationAngle = widget.orientation == HexagonOrientation.pointyTop
        ? 90.0 * (3.14159 / 180.0)
        : 0.0;

    return GestureDetector(
      onTapDown: (_) => _handleTapDown(),
      onTapUp: (_) => _handleTapUp(),
      onTapCancel: _handleTapUp,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final glowAlpha = _controller.value * 0.9;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: glowAlpha > 0
                  ? [BoxShadow(color: Colors.white.withValues(alpha: glowAlpha), blurRadius: 24, spreadRadius: 8)]
                  : [],
            ),
            child: child,
          );
        },
        child: ScaleTransition(
          scale: _scale,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Transform.rotate(
              angle: rotationAngle,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/hexagons/hex_00.svg',
                    width: widget.size,
                    height: widget.size,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(hexColor, BlendMode.srcIn),
                  ),
                  SvgPicture.asset(
                    'assets/hexagons/hex_outline.svg',
                    width: widget.size,
                    height: widget.size,
                    fit: BoxFit.contain,
                  ),
                  Transform.rotate(
                    angle: -rotationAngle,
                    child: Text(
                      solfegeLabel,
                      style: TextStyle(
                        fontSize: widget.size * 0.3,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 3,
                            color: Colors.black45,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

