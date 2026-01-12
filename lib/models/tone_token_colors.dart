import 'package:flutter/material.dart';

/// Color mapping for the 12 chromatic notes (offsets 0-11)
/// Based on the chromatic color wheel used in the ear training system
class ToneTokenColors {
  // Private constructor to prevent instantiation
  ToneTokenColors._();

  /// Get color for a chromatic offset (0-11)
  static Color getColor(int chromaticOffset) {
    // Ensure offset is within valid range
    final offset = chromaticOffset % 12;
    return _colorMap[offset] ?? Colors.grey;
  }

  /// Map of chromatic offset to color
  /// Offset 0 = do (C)
  /// Offset 1 = di/ra (C♯/D♭)
  /// Offset 2 = re (D)
  /// etc.
  static const Map<int, Color> _colorMap = {
    0: Color(0xFFFF2100),  // do - Red
    1: Color(0xFFFF8000),  // di/ra - Orange
    2: Color(0xFFFFB000),  // re - Light Orange
    3: Color(0xFFFCE600),  // ri/me - Yellow
    4: Color(0xFF00F4E2),  // mi - Cyan
    5: Color(0xFF0094EF),  // fa - Light Blue
    6: Color(0xFF0025FF),  // fi/se - Blue
    7: Color(0xFF006ADD),  // so - Medium Blue
    8: Color(0xFF7A1DFF),  // si/le - Purple
    9: Color(0xFFF800FF),  // la - Magenta
    10: Color(0xFFFF00DC), // li/te - Pink-Magenta
    11: Color(0xFFFF0080), // ti - Hot Pink
  };

  /// Get all colors as a list (useful for legends, etc.)
  static List<Color> get allColors => List.from(_colorMap.values);

  /// Get color names for display
  static String getColorName(int chromaticOffset) {
    final offset = chromaticOffset % 12;
    return _colorNames[offset] ?? 'Unknown';
  }

  static const Map<int, String> _colorNames = {
    0: 'Red',
    1: 'Orange',
    2: 'Light Orange',
    3: 'Yellow',
    4: 'Cyan',
    5: 'Light Blue',
    6: 'Blue',
    7: 'Medium Blue',
    8: 'Purple',
    9: 'Magenta',
    10: 'Pink-Magenta',
    11: 'Hot Pink',
  };
}
