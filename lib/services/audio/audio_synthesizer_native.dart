import 'package:flutter_soloud/flutter_soloud.dart';
import 'audio_synthesizer.dart';
import '../../models/synth_parameters.dart';

/// Native implementation of NoteHandle
class NativeNoteHandle implements NoteHandle {
  final SoLoud soloud;
  final SoundHandle handle;
  final AudioSource sound;
  bool _released = false;

  NativeNoteHandle({
    required this.soloud,
    required this.handle,
    required this.sound,
  });

  @override
  void release() {
    if (_released) return;
    _released = true;

    // Stop and cleanup
    soloud.stop(handle);
    soloud.disposeSource(sound);
    print('Note released (native)');
  }
}

/// Native implementation using SoLoud (iOS, Android, macOS, Windows, Linux)
class AudioSynthesizerImpl implements AudioSynthesizer {
  SoLoud? _soloud;
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _soloud = SoLoud.instance;
      await _soloud!.init();
      _isInitialized = true;
      print('SoLoud initialized for native platform');
    } catch (e) {
      print('Error initializing SoLoud: $e');
      rethrow;
    }
  }

  /// Convert OscillatorType to SoLoud WaveForm
  WaveForm _getWaveForm(OscillatorType type) {
    switch (type) {
      case OscillatorType.sine:
        return WaveForm.sin;
      case OscillatorType.square:
        return WaveForm.square;
      case OscillatorType.triangle:
        return WaveForm.triangle;
    }
  }

  @override
  Future<NoteHandle> noteOn(double frequency, SynthParameters params) async {
    if (!_isInitialized || _soloud == null) {
      await initialize();
    }

    // Load waveform based on oscillator type
    final sound = await _soloud!.loadWaveform(
      _getWaveForm(params.oscillatorType),
      false, // superWave
      0.5, // scale/amplitude
      0.0, // detune
    );

    final handle = await _soloud!.play(
      sound,
      volume: params.sustain * 0.5,
    );

    // Adjust pitch to match frequency
    _soloud!.setRelativePlaySpeed(handle, frequency / 261.63);

    print('Note on (native): ${params.oscillatorType.name} at $frequency Hz');

    return NativeNoteHandle(
      soloud: _soloud!,
      handle: handle,
      sound: sound,
    );
  }

  @override
  Future<void> playTone(double frequency, SynthParameters params) async {
    final handle = await noteOn(frequency, params);
    
    // Auto-release after sustain duration
    Future.delayed(const Duration(milliseconds: 200), () {
      handle.release();
    });
  }

  @override
  Future<void> dispose() async {
    if (_soloud != null) {
      _soloud!.deinit();
      _soloud = null;
    }
    _isInitialized = false;
  }
}
