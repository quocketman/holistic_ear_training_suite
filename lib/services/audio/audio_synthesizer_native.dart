import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_synthesizer.dart';
import '../../models/synth_parameters.dart';

/// Native implementation of NoteHandle.
///
/// Implements an ADSR envelope using SoLoud's [fadeVolume] for attack/decay
/// and release. Cancels pending decay if release happens during attack.
class NativeNoteHandle implements NoteHandle {
  final SoLoud soloud;
  final SoundHandle handle;
  final AudioSource sound;
  final double releaseSeconds;
  Timer? _decayTimer;
  Timer? _stopTimer;
  bool _released = false;

  NativeNoteHandle({
    required this.soloud,
    required this.handle,
    required this.sound,
    required this.releaseSeconds,
  });

  @override
  void release() {
    if (_released) return;
    _released = true;

    // Cancel any pending decay fade.
    _decayTimer?.cancel();
    _stopTimer?.cancel();

    // Fade volume to 0 over the release time. fadeVolume picks up from the
    // current volume, so this avoids clicks even mid-attack/decay.
    final releaseMs = (releaseSeconds * 1000).clamp(1, 5000).toInt();
    try {
      soloud.fadeVolume(handle, 0.0, Duration(milliseconds: releaseMs));
    } catch (_) {
      // If fade fails (engine torn down), just stop directly.
    }

    // Stop and dispose after release completes.
    _stopTimer = Timer(Duration(milliseconds: releaseMs + 50), () {
      try {
        soloud.stop(handle);
        soloud.disposeSource(sound);
      } catch (_) {
        // Ignore — engine may have been torn down.
      }
    });
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
      // flutter_soloud needs a temp dir under the cache folder. In a macOS
      // sandbox, the cache folder may not exist yet — create it.
      try {
        final cacheDir = await getApplicationCacheDirectory();
        if (!await cacheDir.exists()) {
          await cacheDir.create(recursive: true);
        }
      } catch (_) {
        // path_provider might fail on some platforms; SoLoud may still work.
      }

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

    final sound = await _soloud!.loadWaveform(
      _getWaveForm(params.oscillatorType),
      false, // superWave
      0.5, // scale/amplitude
      0.0, // detune
    );

    // Optionally activate per-source biquad lowpass filter when the cutoff
    // is below max or resonance is above 0. (Per-source filters not
    // supported on web — that's handled by the web synth implementation.)
    final wantFilter =
        params.filterCutoff < 1.0 || params.filterResonance > 0.0;
    if (wantFilter) {
      try {
        sound.filters.biquadFilter.activate();
      } catch (_) {
        // already active or unsupported — ignore
      }
    }

    const peakVolume = 0.5;
    final sustainVolume = params.sustain * 0.5;
    final attackMs = (params.attack * 1000).clamp(1, 5000).toInt();
    final decayMs = (params.decay * 1000).clamp(1, 5000).toInt();

    // Start silent so attack ramp is audible.
    final handle = await _soloud!.play(sound, volume: 0.0);

    // Set per-handle filter parameters after play.
    if (wantFilter) {
      try {
        // Map cutoff (0-1) → ~100Hz to 16000Hz (logarithmic-ish).
        final cutoffHz = 100.0 + params.filterCutoff * 15900.0;
        sound.filters.biquadFilter
            .frequency(soundHandle: handle)
            .value = cutoffHz;
        // Map resonance (0-1) → 0.1 to 20.
        final resonance = 0.1 + params.filterResonance * 19.9;
        sound.filters.biquadFilter
            .resonance(soundHandle: handle)
            .value = resonance;
      } catch (e) {
        print('Filter setup error: $e');
      }
    }

    // Adjust pitch to match frequency (waveform is C4 = 261.63 Hz).
    _soloud!.setRelativePlaySpeed(handle, frequency / 261.63);

    // Attack: fade from 0 → peak.
    _soloud!.fadeVolume(
      handle,
      peakVolume,
      Duration(milliseconds: attackMs),
    );

    final note = NativeNoteHandle(
      soloud: _soloud!,
      handle: handle,
      sound: sound,
      releaseSeconds: params.release,
    );

    // Decay: schedule fade from peak → sustain after attack completes.
    note._decayTimer = Timer(Duration(milliseconds: attackMs), () {
      if (note._released) return;
      try {
        _soloud!.fadeVolume(
          handle,
          sustainVolume,
          Duration(milliseconds: decayMs),
        );
      } catch (_) {
        // Ignore.
      }
    });

    print('Note on (native): ${params.oscillatorType.name} at $frequency Hz '
        '(A=${params.attack}s D=${params.decay}s S=${params.sustain} '
        'R=${params.release}s, cutoff=${params.filterCutoff})');

    return note;
  }

  @override
  Future<void> playTone(double frequency, SynthParameters params) async {
    final handle = await noteOn(frequency, params);

    // Auto-release after a short sustain duration.
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
