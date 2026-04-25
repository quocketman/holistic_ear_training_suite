import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/enums.dart';
import '../models/tone_token_colors.dart';

/// Static hexagonal token rendered from a raw solfège label and chromatic
/// offset, independent of [MusicalState]. Used in the sequence canvas where
/// the user's typed syllable is shown verbatim.
class SolfegeHexToken extends StatelessWidget {
  final String label;
  final int chromaticOffset;
  final double size;
  final HexagonOrientation orientation;

  const SolfegeHexToken({
    super.key,
    required this.label,
    required this.chromaticOffset,
    this.size = 80.0,
    this.orientation = HexagonOrientation.pointyTop,
  });

  @override
  Widget build(BuildContext context) {
    final hexColor = ToneTokenColors.getColor(chromaticOffset);
    final rotationAngle = orientation == HexagonOrientation.pointyTop
        ? 90.0 * (3.14159 / 180.0)
        : 0.0;

    return SizedBox(
      width: size,
      height: size,
      child: Transform.rotate(
        angle: rotationAngle,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SvgPicture.asset(
              'assets/hexagons/hex_00.svg',
              width: size,
              height: size,
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(hexColor, BlendMode.srcIn),
            ),
            SvgPicture.asset(
              'assets/hexagons/hex_outline.svg',
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
            Transform.rotate(
              angle: -rotationAngle,
              child: Text(
                label,
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
    );
  }
}
