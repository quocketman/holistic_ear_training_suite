import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'note_nugget.dart';
import 'enums.dart';

/// Global musical context that converts relative pitches to absolute pitches
/// Manages the current key, mode, and tempo
class MusicalState extends ChangeNotifier {
  Mode _currentMode;
  int _currentTonic; // MIDI note number (48 = C3 by default)
  int _currentTempo; // BPM

  MusicalState({
    Mode currentMode = Mode.major,
    int currentTonic = 48, // C3
    int currentTempo = 120,
  })  : _currentMode = currentMode,
        _currentTonic = currentTonic,
        _currentTempo = currentTempo;

  // Getters
  Mode get currentMode => _currentMode;
  int get currentTonic => _currentTonic;
  int get currentTempo => _currentTempo;
  
  PitchClass get currentTonicPitchClass => 
      PitchClass.fromMidi(_currentTonic);

  // Setters with notification
  set currentMode(Mode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      notifyListeners();
    }
  }

  set currentTonic(int tonic) {
    if (_currentTonic != tonic) {
      _currentTonic = tonic;
      notifyListeners();
    }
  }

  set currentTempo(int tempo) {
    if (_currentTempo != tempo) {
      _currentTempo = tempo;
      notifyListeners();
    }
  }

  /// Get the solfège syllable for a NoteNugget in the current key/mode
  /// This accounts for mode-specific alterations
  String solfegeFromCurrentKey(NoteNugget nugget) {
    // Get the mode's characteristic solfège for this scale degree
    final modeBaseSolfege = _currentMode.solfegeNames[nugget.scaleDegree - 1];
    
    // If there's a chromatic alteration, modify the syllable
    if (nugget.chromaticAlteration == 0) {
      return modeBaseSolfege;
    } else if (nugget.chromaticAlteration == 1) {
      // Raised version
      return _raisedSolfege(modeBaseSolfege);
    } else {
      // Lowered version
      return _loweredSolfege(modeBaseSolfege);
    }
  }

  /// Get raised version of a solfège syllable
  String _raisedSolfege(String solfege) {
    const raisedMap = {
      'do': 'di',
      're': 'ri',
      'me': 'mi',
      'mi': 'mi', // Already raised
      'fa': 'fi',
      'so': 'si',
      'le': 'la',
      'la': 'li',
      'te': 'ti',
      'ti': 'ti', // Already raised
      'ra': 're',
      'se': 'so',
    };
    return raisedMap[solfege] ?? solfege;
  }

  /// Get lowered version of a solfège syllable
  String _loweredSolfege(String solfege) {
    const loweredMap = {
      'do': 'ti', // Lowered do wraps to ti below
      'di': 'do',
      're': 'ra',
      'ri': 're',
      'mi': 'me',
      'me': 'me', // Already lowered
      'fa': 'mi',
      'fi': 'fa',
      'so': 'se',
      'si': 'so',
      'la': 'le',
      'li': 'la',
      'ti': 'te',
      'te': 'te', // Already lowered
    };
    return loweredMap[solfege] ?? solfege;
  }

  /// Convert a NoteNugget to an absolute MIDI note number
  /// Takes into account current tonic, mode, and octave displacement
  int getMidiNote(NoteNugget nugget) {
    // Get the semitone offset for this scale degree in the current mode
    final scaleOffset = _currentMode.offsets[nugget.scaleDegree - 1];
    
    // Calculate final MIDI note
    final midiNote = _currentTonic +
        scaleOffset +
        nugget.chromaticAlteration +
        (nugget.octave * 12);
    
    return midiNote;
  }

  /// Get the frequency in Hz for a NoteNugget
  /// Uses A4 = 440 Hz as reference
  double getFrequency(NoteNugget nugget) {
    final midiNote = getMidiNote(nugget);
    // MIDI note 69 = A4 = 440 Hz
    return 440.0 * math.pow(2.0, (midiNote - 69) / 12.0);
  }

  @override
  String toString() {
    return 'MusicalState(mode: ${_currentMode.name}, '
        'tonic: ${currentTonicPitchClass.displayName}, '
        'tempo: $_currentTempo BPM)';
  }
}
