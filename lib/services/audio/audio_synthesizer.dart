import '../../models/synth_parameters.dart';

/// Handle for an active note that can be released
abstract class NoteHandle {
  /// Release the note (trigger the release phase of ADSR)
  void release();
}

/// Abstract interface for platform-specific audio synthesis
/// Each platform implements this to provide tone generation
abstract class AudioSynthesizer {
  /// Initialize the audio engine
  Future<void> initialize();

  /// Start playing a tone at the given frequency
  /// Returns a handle that can be used to release the note
  /// [frequency] in Hz
  /// [params] synthesizer parameters (oscillator, filter, ADSR)
  Future<NoteHandle> noteOn(double frequency, SynthParameters params);

  /// Play a tone for a fixed duration (legacy method)
  /// [frequency] in Hz
  /// [params] synthesizer parameters (oscillator, filter, ADSR)
  Future<void> playTone(double frequency, SynthParameters params);

  /// Clean up resources
  Future<void> dispose();

  /// Whether the synthesizer is initialized
  bool get isInitialized;
}
