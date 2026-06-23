import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/musical_state.dart';
import '../services/audio_service.dart';
import 'solfege_hex_token.dart';

/// Full-screen "find the key" overlay. Shows a centered "do" hex with an
/// up and down arrow flanking it; each arrow shifts the tonic ±1 semitone
/// and plays the new "do". No note name is ever shown — the entire point
/// is that the user finds the key purely by ear (taught via the email
/// course). The AppBar's key picker still reflects the change for after
/// the user dismisses the overlay.
class FindTheKeyModal extends StatefulWidget {
  final AudioService audioService;
  final SolfegeHexTheme theme;

  const FindTheKeyModal({
    super.key,
    required this.audioService,
    required this.theme,
  });

  @override
  State<FindTheKeyModal> createState() => _FindTheKeyModalState();
}

class _FindTheKeyModalState extends State<FindTheKeyModal> {
  NoteHandle? _activeHandle;

  @override
  void initState() {
    super.initState();
    // Sound the starting "do" once on open so the user has an anchor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playDo(context.read<MusicalState>().currentTonic);
    });
  }

  @override
  void dispose() {
    _activeHandle?.release();
    super.dispose();
  }

  Future<void> _playDo(int midi) async {
    if (midi < 0 || midi > 127) return;
    // Release the previous tone so successive taps don't pile up sustains.
    _activeHandle?.release();
    _activeHandle = null;
    final handle = await widget.audioService.noteOn(
      midi,
      params: AudioService.globalSynthParams,
    );
    if (handle == null) return;
    _activeHandle = handle;
    // Hold the note ~1.5 s so the user can hear the sustained pitch and
    // imagine it against the melody in their head, then release.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_activeHandle == handle) {
        handle.release();
        _activeHandle = null;
      }
    });
  }

  void _step(int delta, MusicalState state) {
    final next = (state.currentTonic + delta).clamp(0, 127);
    if (next == state.currentTonic) return;
    state.currentTonic = next;
    _playDo(next);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.theme == SolfegeHexTheme.light;
    final bgColor = isLight ? Colors.white : Colors.black;
    final fgColor = isLight ? Colors.black : Colors.white;

    return Dialog.fullscreen(
      backgroundColor: bgColor,
      child: Consumer<MusicalState>(
        builder: (context, state, _) {
          return SafeArea(
            child: Stack(
              children: [
                // Close (top-right). Dismissing returns to the editor with
                // the new tonic already applied via the shared MusicalState.
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    icon: Icon(Icons.close, color: fgColor, size: 30),
                    tooltip: 'Done',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                // Centered column: up arrow, hex, down arrow.
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ArrowButton(
                        icon: Icons.keyboard_arrow_up,
                        tooltip: 'Up a half-step',
                        onPressed: () => _step(1, state),
                        isLight: isLight,
                      ),
                      const SizedBox(height: 24),
                      // Tap the hex to replay the current "do" without
                      // changing the key — useful after losing the pitch.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _playDo(state.currentTonic),
                        child: const _DoHex(),
                      ),
                      const SizedBox(height: 24),
                      _ArrowButton(
                        icon: Icons.keyboard_arrow_down,
                        tooltip: 'Down a half-step',
                        onPressed: () => _step(-1, state),
                        isLight: isLight,
                      ),
                    ],
                  ),
                ),
                // Subtle ear-only instruction at the bottom — no note names.
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Text(
                    'Tap ↑ or ↓ until "do" matches the pitch in your head. '
                    'Tap the hex to replay.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sourceSans3(
                      fontSize: 15,
                      color: fgColor.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Centered "do" hex token. Always renders in the dark state so the visual
/// is identical to how "do" appears on the editor canvas.
class _DoHex extends StatelessWidget {
  const _DoHex();

  @override
  Widget build(BuildContext context) {
    // Size scales with the narrower screen dimension so it dominates the
    // overlay on phones without overflowing on desktops.
    final shortSide = MediaQuery.of(context).size.shortestSide;
    final size = (shortSide * 0.38).clamp(160.0, 280.0);
    return SolfegeHexToken(
      label: 'do',
      chromaticOffset: 0,
      size: size,
      state: SolfegeHexState.dark,
    );
  }
}

/// Circular ↑/↓ button styled to read against either theme. Generous tap
/// area for touch users (96 px), large arrow glyph for unambiguous intent.
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isLight;

  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor = isLight
        ? Colors.black.withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.95);
    final iconColor = isLight ? Colors.white : Colors.black;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: fillColor,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 96,
            height: 96,
            child: Center(
              child: Icon(icon, size: 56, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}
