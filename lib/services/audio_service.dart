import 'package:just_audio/just_audio.dart';
import 'dart:math' as math;

import 'audio/audio_synthesizer.dart';
import 'audio/audio_synthesizer_factory.dart';
import '../models/synth_parameters.dart';

// Re-export NoteHandle for external use
export 'audio/audio_synthesizer.dart' show NoteHandle;

/// Service for handling audio playback in ear training exercises
/// Supports web, iOS, Android, macOS, Windows, and Linux
class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  static AudioSynthesizer? _synthesizer;
  static bool _isInitialized = false;

  /// Global synth parameters - shared across all screens
  static final SynthParameters globalSynthParams = SynthParameters();

  /// Initialize the audio synthesizer
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _synthesizer = createAudioSynthesizer();
      await _synthesizer!.initialize();
      _isInitialized = true;
      print('Audio service initialized successfully');
    } catch (e) {
      print('Error initializing audio: $e');
    }
  }

  /// Start a note that sustains until released
  /// Returns a NoteHandle that must be used to release the note
  Future<NoteHandle?> noteOn(int midiNote, {SynthParameters? params}) async {
    if (!_isInitialized || _synthesizer == null) {
      await initialize();
    }

    try {
      final frequency = 440.0 * math.pow(2, (midiNote - 69) / 12);
      final synthParams = params ?? globalSynthParams;
      return await _synthesizer!.noteOn(frequency, synthParams);
    } catch (e) {
      print('Error starting note: $e');
      return null;
    }
  }

  /// Play a synthesized tone at a specific MIDI note number (fixed duration)
  /// Uses either provided params or the global synth parameters
  Future<void> playTone(int midiNote, {SynthParameters? params}) async {
    print('playTone called with MIDI note: $midiNote');

    if (!_isInitialized || _synthesizer == null) {
      print('Audio not initialized, initializing now...');
      await initialize();
    }

    try {
      // Convert MIDI note to frequency: f = 440 * 2^((n-69)/12)
      final frequency = 440.0 * math.pow(2, (midiNote - 69) / 12);
      print('Calculated frequency: $frequency Hz');

      // Use provided params or fall back to global params
      final synthParams = params ?? globalSynthParams;
      await _synthesizer!.playTone(frequency, synthParams);
    } catch (e) {
      print('Error playing tone: $e');
    }
  }

  /// Play an audio file from assets
  Future<void> playAudio(String assetPath) async {
    try {
      await _audioPlayer.setAsset(assetPath);
      await _audioPlayer.play();
    } catch (e) {
      print('Error playing audio: $e');
      rethrow;
    }
  }

  /// Stop currently playing audio
  Future<void> stop() async {
    await _audioPlayer.stop();
  }

  /// Pause currently playing audio
  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  /// Resume paused audio
  Future<void> resume() async {
    await _audioPlayer.play();
  }

  /// Get current playback position
  Duration get currentPosition => _audioPlayer.position;

  /// Get total duration of current audio
  Duration? get duration => _audioPlayer.duration;

  /// Check if audio is currently playing
  bool get isPlaying => _audioPlayer.playing;

  /// Dispose of the audio player
  void dispose() {
    _audioPlayer.dispose();
  }

  /// Clean up synthesizer resources
  static Future<void> cleanup() async {
    if (_synthesizer != null) {
      await _synthesizer!.dispose();
      _synthesizer = null;
    }
    _isInitialized = false;
  }
}
