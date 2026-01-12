import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../models/note_nugget.dart';
import '../models/musical_state.dart';
import '../models/enums.dart';
import '../models/tone_token_colors.dart';

/// Visual representation of a musical note using hexagonal tokens
/// Displays an SVG hexagon with a solfège text label overlay
class ToneToken extends StatelessWidget {
  final NoteNugget noteNugget;
  final double size;
  final HexagonOrientation orientation;
  final VoidCallback? onTap;

  const ToneToken({
    super.key,
    required this.noteNugget,
    this.size = 80.0,
    this.orientation = HexagonOrientation.flatTop,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final musicalState = context.watch<MusicalState>();
    final solfegeLabel = musicalState.solfegeFromCurrentKey(noteNugget);
    
    // Get chromatic offset and corresponding color
    final chromaticOffset = noteNugget.getChromaticOffset(musicalState.currentMode);
    final hexColor = ToneTokenColors.getColor(chromaticOffset);
    
    // Determine rotation based on orientation
    final rotationAngle = orientation == HexagonOrientation.pointyTop 
        ? 90.0 * (3.14159 / 180.0)  // 90 degrees in radians
        : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Transform.rotate(
          angle: rotationAngle,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // SVG hexagon background with color filter
              SvgPicture.asset(
                'assets/hexagons/hex_00.svg', // Use first hexagon as default
                width: size,
                height: size,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(hexColor, BlendMode.srcIn),
              ),
              
              // Solfège text label
              Transform.rotate(
                angle: -rotationAngle, // Counter-rotate text to keep it upright
                child: Text(
                  solfegeLabel,
                  style: TextStyle(
                    fontSize: size * 0.3,
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
    );
  }
}
