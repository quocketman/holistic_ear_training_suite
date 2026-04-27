import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/tone_token_colors.dart';

/// Static hexagonal token rendered from a raw solfège label and chromatic
/// offset, independent of [MusicalState]. Used in the sequence canvas where
/// the user's typed syllable is shown verbatim.
///
/// Flat-top hex with black fill, solfège-colored outline and text.
class SolfegeHexToken extends StatelessWidget {
  final String label;
  final int chromaticOffset;
  final double size;

  const SolfegeHexToken({
    super.key,
    required this.label,
    required this.chromaticOffset,
    this.size = 80.0,
  });

  @override
  Widget build(BuildContext context) {
    final hexColor = ToneTokenColors.getColor(chromaticOffset);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Black fill.
          SvgPicture.asset(
            'assets/hexagons/hex_00.svg',
            width: size,
            height: size,
            fit: BoxFit.contain,
            colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          ),
          // Colored outline.
          SvgPicture.asset(
            'assets/hexagons/hex_outline_thick.svg',
            width: size,
            height: size,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(hexColor, BlendMode.srcIn),
          ),
          // Colored text.
          Text(
            label,
            style: GoogleFonts.sourceSans3(
              fontSize: size * 0.3,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
