/// Musical modes with their characteristic scale patterns
enum Mode {
  lydian,
  major,
  mixolydian,
  dorian,
  minorNatural,
  minorHarmonic,
  minorMelodic,
  phrygian,
  locrian;

  /// Get the semitone offsets for each scale degree in this mode
  List<int> get offsets {
    switch (this) {
      case Mode.lydian:
        return [0, 2, 4, 6, 7, 9, 11];
      case Mode.major:
        return [0, 2, 4, 5, 7, 9, 11];
      case Mode.mixolydian:
        return [0, 2, 4, 5, 7, 9, 10];
      case Mode.dorian:
        return [0, 2, 3, 5, 7, 9, 10];
      case Mode.minorNatural:
        return [0, 2, 3, 5, 7, 8, 10];
      case Mode.minorHarmonic:
        return [0, 2, 3, 5, 7, 8, 11];
      case Mode.minorMelodic:
        return [0, 2, 3, 5, 7, 9, 11];
      case Mode.phrygian:
        return [0, 1, 3, 5, 7, 8, 10];
      case Mode.locrian:
        return [0, 1, 3, 5, 6, 8, 10];
    }
  }

  /// Get the solfège syllables for this mode's scale degrees
  /// These account for the mode's characteristic alterations
  List<String> get solfegeNames {
    switch (this) {
      case Mode.major:
      case Mode.lydian:
        return ['do', 're', 'mi', 'fa', 'so', 'la', 'ti'];
      case Mode.mixolydian:
        return ['do', 're', 'mi', 'fa', 'so', 'la', 'te'];
      case Mode.dorian:
        return ['do', 're', 'me', 'fa', 'so', 'la', 'te'];
      case Mode.minorNatural:
      case Mode.minorHarmonic:
      case Mode.minorMelodic:
        return ['do', 're', 'me', 'fa', 'so', 'le', 'ti'];
      case Mode.phrygian:
        return ['do', 'ra', 'me', 'fa', 'so', 'le', 'te'];
      case Mode.locrian:
        return ['do', 'ra', 'me', 'fa', 'se', 'le', 'te'];
    }
  }
}

/// Pitch class (0-11) representing the 12 chromatic pitches
enum PitchClass {
  c(0, 'C'),
  cSharp(1, 'C♯'),
  d(2, 'D'),
  dSharp(3, 'D♯'),
  e(4, 'E'),
  f(5, 'F'),
  fSharp(6, 'F♯'),
  g(7, 'G'),
  gSharp(8, 'G♯'),
  a(9, 'A'),
  aSharp(10, 'A♯'),
  b(11, 'B');

  final int value;
  final String displayName;

  const PitchClass(this.value, this.displayName);

  /// Get pitch class from MIDI note number
  static PitchClass fromMidi(int midiNote) {
    final pitchClass = midiNote % 12;
    return PitchClass.values.firstWhere((pc) => pc.value == pitchClass);
  }
}

/// Orientation of hexagon tokens
enum HexagonOrientation {
  flatTop, // Horizontal orientation (flat side on top)
  pointyTop; // Vertical orientation (point on top)
}
