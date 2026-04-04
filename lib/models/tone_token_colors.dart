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
    0: Color(0xFFFF2100), // do - Red
    1: Color(0xFFED5500), // ra - Burnt Orange
    2: Color(0xFFFF8000), // re - Orange
    3: Color(0xFFFFB000), // me - Amber
    4: Color(0xFFFCE600), // mi - Yellow
    5: Color(0xFF00BA00), // fa - Green
    6: Color(0xFF2498B3), // fi - Teal
    7: Color(0xFF3F55C7), // so - Blue
    8: Color(0xFF5600DD), // le - Purple
    9: Color(0xFF0053F9), // la - Royal Blue
    10: Color(0xFF7A1DFF), // te - Violet
    11: Color(0xFFE002C2), // ti - Magenta
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
    1: 'Burnt Orange',
    2: 'Orange',
    3: 'Amber',
    4: 'Yellow',
    5: 'Green',
    6: 'Teal',
    7: 'Blue',
    8: 'Purple',
    9: 'Royal Blue',
    10: 'Violet',
    11: 'Magenta',
  };
}
