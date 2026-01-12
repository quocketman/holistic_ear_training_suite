import 'package:just_audio/just_audio.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'dart:math' as math;

/// Service for handling audio playback in ear training exercises
class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  static SoLoud? _soloud;
  static bool _isInitialized = false;
  
  /// Initialize the audio synthesizer
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _soloud = SoLoud.instance;
      
      // Initialize SoLoud
      await _soloud!.init();
      
      _isInitialized = true;
      print('SoLoud initialized successfully');
    } catch (e) {
      print('Error initializing SoLoud: $e');
    }
  }
  
  /// Play a synthesized tone at a specific MIDI note number
  /// duration in milliseconds
  Future<void> playTone(int midiNote, {int duration = 500}) async {
    print('playTone called with MIDI note: $midiNote');
    
    if (!_isInitialized || _soloud == null) {
      print('SoLoud not initialized, initializing now...');
      await initialize();
    }
    
    try {
      // Convert MIDI note to frequency: f = 440 * 2^((n-69)/12)
      final frequency = 440.0 * math.pow(2, (midiNote - 69) / 12);
      print('Calculated frequency: $frequency Hz');
      
      // Load and play a basic waveform (square wave)
      print('Loading waveform...');
      final sound = await _soloud!.loadWaveform(
        WaveForm.square,
        false, // superWave
        0.5,   // scale/amplitude
        0.0,   // detune
      );
      print('Waveform loaded, playing...');
      
      final handle = await _soloud!.play(
        sound,
        volume: 0.5,
      );
      print('Playing with handle: $handle');
      
      // Adjust pitch to match MIDI note frequency
      // Middle C (MIDI 60) = 261.63 Hz, use as reference
      _soloud!.setRelativePlaySpeed(handle, frequency / 261.63);
      print('Set relative play speed: ${frequency / 261.63}');
      
      // Schedule cleanup without blocking
      Future.delayed(Duration(milliseconds: duration)).then((_) {
        _soloud!.stop(handle);
        _soloud!.disposeSource(sound);
        print('Tone finished and disposed');
      });
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
    if (_isInitialized && _soloud != null) {
      _soloud!.deinit();
      _isInitialized = false;
    }
  }
}
