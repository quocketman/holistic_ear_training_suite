import 'enums.dart';

/// Represents a relative pitch in the musical system
/// Does not know absolute pitch - that's determined by MusicalState
class NoteNugget {
  /// Scale degree from 1-7 (musical counting starts at 1)
  final int scaleDegree;

  /// Chromatic alteration: -1 (flat), 0 (natural), +1 (sharp)
  final int chromaticAlteration;

  /// Octave displacement (0 = middle octave)
  final int octave;

  NoteNugget({
    required this.scaleDegree,
    this.chromaticAlteration = 0,
    this.octave = 0,
  })  : assert(scaleDegree >= 1 && scaleDegree <= 7,
            'Scale degree must be between 1 and 7'),
        assert(chromaticAlteration >= -1 && chromaticAlteration <= 1,
            'Chromatic alteration must be -1, 0, or +1');

  /// Get the base solfège syllable (without considering mode)
  /// This returns the chromatic solfège name based on scale degree and alteration
  String getBaseSolfege() {
    // Map of (scaleDegree, chromaticAlteration) to solfège syllable
    const solfegeMap = {
      // Scale step 1 (do)
      (1, -1): 'ti', // Lowered do is ti from below
      (1, 0): 'do',
      (1, 1): 'di', // Raised do

      // Scale step 2 (re)
      (2, -1): 'ra', // Lowered re
      (2, 0): 're',
      (2, 1): 'ri', // Raised re

      // Scale step 3 (mi)
      (3, -1): 'me', // Lowered mi
      (3, 0): 'mi',
      (3, 1): 'mi', // Raised mi (enharmonic with fa)

      // Scale step 4 (fa)
      (4, -1): 'mi', // Lowered fa (enharmonic with mi)
      (4, 0): 'fa',
      (4, 1): 'fi', // Raised fa

      // Scale step 5 (so)
      (5, -1): 'se', // Lowered so
      (5, 0): 'so',
      (5, 1): 'si', // Raised so

      // Scale step 6 (la)
      (6, -1): 'le', // Lowered la
      (6, 0): 'la',
      (6, 1): 'li', // Raised la

      // Scale step 7 (ti)
      (7, -1): 'te', // Lowered ti
      (7, 0): 'ti',
      (7, 1): 'ti', // Raised ti (enharmonic with do above)
    };

    return solfegeMap[(scaleDegree, chromaticAlteration)] ?? 'do';
  }

  /// Get the chromatic offset (0-11) for this note in a given mode
  /// This represents the semitone distance from the tonic
  int getChromaticOffset(Mode mode) {
    final scaleOffset = mode.offsets[scaleDegree - 1];
    final totalOffset = (scaleOffset + chromaticAlteration) % 12;
    return totalOffset < 0 ? totalOffset + 12 : totalOffset;
  }

  /// Get SVG asset name based on chromatic offset
  /// Assets should be named hex_00.svg through hex_11.svg
  String getSvgAssetName(Mode mode) {
    final offset = getChromaticOffset(mode);
    // Format with leading zero for single digits (hex_00 to hex_11)
    final paddedOffset = offset.toString().padLeft(2, '0');
    return 'assets/hexagons/hex_$paddedOffset.svg';
  }

  /// True when two nuggets share scale degree and alteration, ignoring octave.
  /// Used for mapping grid tokens to level notes — the grid represents pitch
  /// classes, while octave only affects audio playback.
  bool samePitchClass(NoteNugget other) =>
      scaleDegree == other.scaleDegree &&
      chromaticAlteration == other.chromaticAlteration;

  @override
  String toString() {
    return 'NoteNugget(degree: $scaleDegree, alt: $chromaticAlteration, oct: $octave)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NoteNugget &&
        other.scaleDegree == scaleDegree &&
        other.chromaticAlteration == chromaticAlteration &&
        other.octave == octave;
  }

  @override
  int get hashCode => Object.hash(scaleDegree, chromaticAlteration, octave);
}
