import 'package:flutter/foundation.dart';

/// Oscillator waveform types
enum OscillatorType { sine, square, triangle }

/// Model class for synthesizer parameters
/// Uses ChangeNotifier for reactive UI updates
class SynthParameters extends ChangeNotifier {
  // Whiteboard launch defaults (Hans's tuned sound, 2026-06-11).
  // To tweak later: edit both these field initializers AND `reset()`.

  // Oscillator
  OscillatorType _oscillatorType = OscillatorType.triangle;

  // Filter (0.0 to 1.0 normalized)
  double _filterCutoff = 0.12;
  double _filterResonance = 0.0;

  // ADSR Envelope (in seconds, except sustain which is 0-1)
  double _attack = 0.02;
  double _decay = 0.10;
  double _sustain = 0.7;
  double _release = 0.38;

  // Getters
  OscillatorType get oscillatorType => _oscillatorType;
  double get filterCutoff => _filterCutoff;
  double get filterResonance => _filterResonance;
  double get attack => _attack;
  double get decay => _decay;
  double get sustain => _sustain;
  double get release => _release;

  // Setters with notification
  set oscillatorType(OscillatorType value) {
    if (_oscillatorType != value) {
      _oscillatorType = value;
      notifyListeners();
    }
  }

  set filterCutoff(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_filterCutoff != clamped) {
      _filterCutoff = clamped;
      notifyListeners();
    }
  }

  set filterResonance(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_filterResonance != clamped) {
      _filterResonance = clamped;
      notifyListeners();
    }
  }

  set attack(double value) {
    final clamped = value.clamp(0.001, 2.0);
    if (_attack != clamped) {
      _attack = clamped;
      notifyListeners();
    }
  }

  set decay(double value) {
    final clamped = value.clamp(0.001, 2.0);
    if (_decay != clamped) {
      _decay = clamped;
      notifyListeners();
    }
  }

  set sustain(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_sustain != clamped) {
      _sustain = clamped;
      notifyListeners();
    }
  }

  set release(double value) {
    final clamped = value.clamp(0.001, 3.0);
    if (_release != clamped) {
      _release = clamped;
      notifyListeners();
    }
  }

  /// Reset to the Whiteboard launch defaults.
  void reset() {
    _oscillatorType = OscillatorType.triangle;
    _filterCutoff = 0.12;
    _filterResonance = 0.0;
    _attack = 0.02;
    _decay = 0.10;
    _sustain = 0.7;
    _release = 0.38;
    notifyListeners();
  }

  @override
  String toString() {
    return 'SynthParameters(osc: ${_oscillatorType.name}, '
        'cutoff: ${_filterCutoff.toStringAsFixed(2)}, '
        'res: ${_filterResonance.toStringAsFixed(2)}, '
        'A: ${_attack.toStringAsFixed(2)}, D: ${_decay.toStringAsFixed(2)}, '
        'S: ${_sustain.toStringAsFixed(2)}, R: ${_release.toStringAsFixed(2)})';
  }
}
