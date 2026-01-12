import 'package:flutter/material.dart';

/// A reusable widget for audio playback controls
class AudioPlayerWidget extends StatefulWidget {
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final bool isPlaying;

  const AudioPlayerWidget({
    super.key,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.isPlaying,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                widget.isPlaying ? Icons.pause_circle : Icons.play_circle,
                size: 64,
              ),
              onPressed: widget.isPlaying ? widget.onPause : widget.onPlay,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 20),
            IconButton(
              icon: const Icon(Icons.stop_circle, size: 48),
              onPressed: widget.onStop,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ],
        ),
      ),
    );
  }
}
