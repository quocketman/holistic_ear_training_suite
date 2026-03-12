// Factory for creating the platform-specific AudioSynthesizer
// Uses conditional imports to select the right implementation

import 'audio_synthesizer.dart';
import 'audio_synthesizer_stub.dart'
    if (dart.library.js_interop) 'audio_synthesizer_web.dart'
    if (dart.library.io) 'audio_synthesizer_native.dart' as impl;

/// Creates the appropriate AudioSynthesizer for the current platform
AudioSynthesizer createAudioSynthesizer() {
  return impl.AudioSynthesizerImpl();
}
