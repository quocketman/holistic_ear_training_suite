import 'audio_synthesizer.dart';
import '../../models/synth_parameters.dart';

/// Stub implementation of NoteHandle
class StubNoteHandle implements NoteHandle {
  @override
  void release() {
    print('Stub: Note released');
  }
}

/// Stub implementation - should never be used at runtime
/// This exists only to satisfy the conditional import when the
/// actual platform implementation can't be resolved at compile time
class AudioSynthesizerImpl implements AudioSynthesizer {
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    print('Warning: Using stub audio synthesizer');
    _isInitialized = true;
  }

  @override
  Future<NoteHandle> noteOn(double frequency, SynthParameters params) async {
    print('Stub: Note on ${params.oscillatorType.name} at $frequency Hz');
    return StubNoteHandle();
  }

  @override
  Future<void> playTone(double frequency, SynthParameters params) async {
    print('Stub: Would play ${params.oscillatorType.name} at $frequency Hz');
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
  }
}
