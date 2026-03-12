import 'package:web/web.dart' as web;
import 'audio_synthesizer.dart';
import '../../models/synth_parameters.dart';

/// Web implementation of NoteHandle
class WebNoteHandle implements NoteHandle {
  final web.OscillatorNode oscillator;
  final web.GainNode gainNode;
  final web.AudioContext context;
  final double sustainLevel;
  final double releaseTime;
  bool _released = false;

  WebNoteHandle({
    required this.oscillator,
    required this.gainNode,
    required this.context,
    required this.sustainLevel,
    required this.releaseTime,
  });

  @override
  void release() {
    if (_released) return;
    _released = true;

    final currentTime = context.currentTime;

    // Cancel any scheduled ramps - this is crucial to avoid clicks
    gainNode.gain.cancelScheduledValues(currentTime);

    // Get the actual current gain value (may be mid-attack or mid-decay)
    // This avoids the click from jumping to sustainLevel
    final currentGain = gainNode.gain.value;

    // Set from actual current value, not the scheduled sustain level
    gainNode.gain.setValueAtTime(currentGain, currentTime);

    // Ramp to zero over the release time
    gainNode.gain.linearRampToValueAtTime(0.0, currentTime + releaseTime);

    // Stop oscillator after release completes
    oscillator.stop(currentTime + releaseTime + 0.01);

    print('Note released from gain $currentGain');
  }
}

/// Web implementation using Web Audio API
class AudioSynthesizerImpl implements AudioSynthesizer {
  web.AudioContext? _audioContext;
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioContext = web.AudioContext();
      _isInitialized = true;
      print('Web Audio API initialized');
    } catch (e) {
      print('Error initializing Web Audio: $e');
      rethrow;
    }
  }

  /// Convert OscillatorType enum to Web Audio oscillator type string
  String _getOscillatorType(OscillatorType type) {
    switch (type) {
      case OscillatorType.sine:
        return 'sine';
      case OscillatorType.square:
        return 'square';
      case OscillatorType.triangle:
        return 'triangle';
    }
  }

  @override
  Future<NoteHandle> noteOn(double frequency, SynthParameters params) async {
    if (!_isInitialized || _audioContext == null) {
      await initialize();
    }

    final ctx = _audioContext!;
    final currentTime = ctx.currentTime;

    // Get ADSR values from params
    final attack = params.attack;
    final decay = params.decay;
    final sustainLevel = params.sustain * 0.5; // Scale to max 0.5 volume
    final release = params.release;

    // Create oscillator with selected type
    final oscillator = ctx.createOscillator();
    oscillator.type = _getOscillatorType(params.oscillatorType);
    oscillator.frequency.value = frequency;

    // Create filter (lowpass)
    final filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    final cutoffFreq = 200 * (100.0 * params.filterCutoff).clamp(1.0, 100.0);
    filter.frequency.value = cutoffFreq;
    filter.Q.value = 0.5 + params.filterResonance * 14.5;

    // Create gain node for ADSR envelope
    final gainNode = ctx.createGain();
    gainNode.gain.value = 0.0;

    // Connect: oscillator -> filter -> gain -> output
    oscillator.connect(filter);
    filter.connect(gainNode);
    gainNode.connect(ctx.destination);

    // Attack and Decay phases (sustain indefinitely until release)
    double t = currentTime;

    // Attack: 0 -> peak (0.5)
    gainNode.gain.setValueAtTime(0.0, t);
    t += attack;
    gainNode.gain.linearRampToValueAtTime(0.5, t);

    // Decay: peak -> sustain level
    t += decay;
    gainNode.gain.linearRampToValueAtTime(sustainLevel, t);

    // Start oscillator (will sustain until release() is called)
    oscillator.start(currentTime);

    print('Note on: ${params.oscillatorType.name} wave at $frequency Hz');

    return WebNoteHandle(
      oscillator: oscillator,
      gainNode: gainNode,
      context: ctx,
      sustainLevel: sustainLevel,
      releaseTime: release,
    );
  }

  @override
  Future<void> playTone(double frequency, SynthParameters params) async {
    // Fixed duration playback (for backwards compatibility)
    final handle = await noteOn(frequency, params);

    // Auto-release after sustain duration
    Future.delayed(const Duration(milliseconds: 200), () {
      handle.release();
    });
  }

  @override
  Future<void> dispose() async {
    if (_audioContext != null) {
      _audioContext!.close();
      _audioContext = null;
    }
    _isInitialized = false;
  }
}
