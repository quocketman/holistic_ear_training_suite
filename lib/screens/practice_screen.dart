import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_nugget.dart';
import '../models/level_specs.dart';
import '../models/musical_state.dart';
import '../models/practice_session.dart';
import '../services/audio_service.dart';
import '../widgets/tone_token.dart';
import '../models/enums.dart';

/// Full chromatic scale — shared by the grid and the state for key lookup.
/// Index 0 = high do, 1–11 = ra through ti, 12 = low do (one octave below).
final _chromaticScale = [
  NoteNugget(scaleDegree: 1, chromaticAlteration: 0),            // 0: do
  NoteNugget(scaleDegree: 1, chromaticAlteration: 1),            // 1: di/ra
  NoteNugget(scaleDegree: 2, chromaticAlteration: 0),            // 2: re
  NoteNugget(scaleDegree: 3, chromaticAlteration: -1),           // 3: me
  NoteNugget(scaleDegree: 3, chromaticAlteration: 0),            // 4: mi
  NoteNugget(scaleDegree: 4, chromaticAlteration: 0),            // 5: fa
  NoteNugget(scaleDegree: 4, chromaticAlteration: 1),            // 6: fi
  NoteNugget(scaleDegree: 5, chromaticAlteration: 0),            // 7: so
  NoteNugget(scaleDegree: 6, chromaticAlteration: -1),           // 8: le
  NoteNugget(scaleDegree: 6, chromaticAlteration: 0),            // 9: la
  NoteNugget(scaleDegree: 7, chromaticAlteration: -1),           // 10: te
  NoteNugget(scaleDegree: 7, chromaticAlteration: 0),            // 11: ti
  NoteNugget(scaleDegree: 1, chromaticAlteration: 0, octave: -1), // 12: low do
];

/// Default level: diatonic major scale, single notes, random order.
final _defaultLevelSpecs = LevelSpecs(
  id: 'default',
  levelTitle: 'Major Scale — Single Notes',
  availableNoteNuggets: [
    NoteNugget(scaleDegree: 1),
    NoteNugget(scaleDegree: 2),
    NoteNugget(scaleDegree: 3),
    NoteNugget(scaleDegree: 4),
    NoteNugget(scaleDegree: 5),
    NoteNugget(scaleDegree: 6),
    NoteNugget(scaleDegree: 7),
  ],
  howManyAtATime: 1,
  howManyInARow: 1,
  noTwiceInARow: true,
  answerTokensMakeASound: true,
  puzzleGenerationMethod: PuzzleGenerationMethod.random,
  questionTokenSymbolMode: QuestionTokenSymbolMode.textAndColor,
  preferredFirstNote: NoteNugget(scaleDegree: 1),
);

class PracticeScreen extends StatefulWidget {
  final LevelSpecs levelSpecs;

  PracticeScreen({
    super.key,
    LevelSpecs? levelSpecs,
  }) : levelSpecs = levelSpecs ?? _defaultLevelSpecs;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final AudioService _audioService = AudioService();
  late final PracticeSession _session;
  bool _pulsing = false;
  bool _sessionStarted = false;
  bool _sequencePlaying = false;
  bool _showRoundEnd = false;
  NoteNugget? _glowingNugget;
  NoteNugget? _wrongNugget;
  OverlayEntry? _splashEntry;

  /// Stable GlobalKeys for each token in the chromatic scale.
  late final Map<NoteNugget, GlobalKey> _tokenKeys;

  @override
  void initState() {
    super.initState();
    _tokenKeys = {for (final n in _chromaticScale) n: GlobalKey()};
    final musicalState = context.read<MusicalState>();
    _session = PracticeSession(
      levelSpecs: widget.levelSpecs,
      musicalState: musicalState,
    );
    _session.addListener(_onSessionChanged);
    _session.nextQuestion(); // primes the first question, but doesn't play yet
  }

  @override
  void dispose() {
    _splashEntry?.remove();
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _audioService.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (_session.lastResult == AnswerResult.correct) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() => _glowingNugget = null);
          if (!_session.roundComplete) {
            _session.nextQuestion();
            _playCurrentQuestion();
          } else {
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted) setState(() => _showRoundEnd = true);
            });
          }
        }
      });
    } else if (_session.lastResult == null && _sessionStarted) {
      _playCurrentQuestion();
    }
  }

  void _startOrReplay() {
    if (!_sessionStarted) {
      setState(() => _sessionStarted = true);
    }
    _playCurrentQuestion();
  }

  Future<void> _playCurrentQuestion() async {
    final question = _session.currentQuestion;
    if (question == null) return;
    final musicalState = context.read<MusicalState>();
    final midiNote = musicalState.getMidiNote(question);
    setState(() => _pulsing = true);
    await _audioService.playTone(midiNote);
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _pulsing = false);
    });
  }

  /// Resolve a grid token (pitch-class position) to the level's actual
  /// NoteNugget which carries the correct octave for audio and scoring.
  NoteNugget? _resolveToLevelNugget(NoteNugget gridNugget) {
    try {
      return widget.levelSpecs.availableNoteNuggets
          .firstWhere((n) => n.samePitchClass(gridNugget));
    } catch (_) {
      return null;
    }
  }

  void _onTokenTapped(NoteNugget gridNugget) {
    if (_sequencePlaying || _session.lastResult != null) return;

    final levelNugget = _resolveToLevelNugget(gridNugget);
    if (levelNugget == null) return;

    final result = _session.submitAnswer(levelNugget);

    if (result == AnswerResult.correct) {
      if (widget.levelSpecs.answerTokensMakeASound) {
        final musicalState = context.read<MusicalState>();
        _audioService.playTone(musicalState.getMidiNote(levelNugget));
      }
      setState(() => _glowingNugget = levelNugget);
      _showSplash(gridNugget);
    } else {
      _playWrongSequence(gridNugget);
    }
  }

  Future<void> _playWrongSequence(NoteNugget wrongNugget) async {
    final question = _session.currentQuestion;
    if (question == null) return;
    final musicalState = context.read<MusicalState>();
    final questionMidi = musicalState.getMidiNote(question);
    final wrongMidi = musicalState.getMidiNote(wrongNugget);

    setState(() => _sequencePlaying = true);

    for (int i = 0; i < 2; i++) {
      if (!mounted) return;
      setState(() { _pulsing = true; _wrongNugget = null; });
      _audioService.playTone(questionMidi);
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      setState(() { _pulsing = false; _wrongNugget = wrongNugget; });
      _audioService.playTone(wrongMidi);
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;
    setState(() { _wrongNugget = null; _sequencePlaying = false; });
  }

  void _showSplash(NoteNugget nugget) {
    final key = _tokenKeys[nugget];
    if (key == null) return;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    final center = Offset(pos.dx + size.width / 2, pos.dy + size.height / 2);

    final musicalState = context.read<MusicalState>();
    final solfege = musicalState.solfegeFromCurrentKey(nugget);

    _splashEntry?.remove();
    _splashEntry = OverlayEntry(
      builder: (_) => _SplashEffect(
        center: center,
        label: solfege,
        onDone: () {
          _splashEntry?.remove();
          _splashEntry = null;
        },
      ),
    );
    Overlay.of(context).insert(_splashEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _session,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.levelSpecs.levelTitle),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Consumer<PracticeSession>(
          builder: (context, session, _) {
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _ScoreBar(session: session),
                      const SizedBox(height: 16),
                      _FeedbackDisplay(result: session.lastResult),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _TokenGrid(
                          levelSpecs: widget.levelSpecs,
                          mode: context.read<MusicalState>().currentMode,
                          glowingNugget: _glowingNugget,
                          wrongNugget: _wrongNugget,
                          tokenKeys: _tokenKeys,
                          onTap: _onTokenTapped,
                          playButton: _PlayButton(onPlay: _startOrReplay, pulsing: _pulsing),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                if (_showRoundEnd)
                  _RoundEndOverlay(
                    session: session,
                    onRestart: () => setState(() {
                _showRoundEnd = false;
                _session.restart();
              }),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  final PracticeSession session;
  const _ScoreBar({required this.session});

  @override
  Widget build(BuildContext context) {
    final specs = session.levelSpecs;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _chip(Icons.music_note, '${session.questionsAnswered}/${specs.questionsPerRound}', Colors.white70),
        const SizedBox(width: 24),
        _chip(Icons.star_outline, '${session.totalPoints}', _pointsColor(session, specs)),
      ],
    );
  }

  Color _pointsColor(PracticeSession s, LevelSpecs specs) {
    if (s.roundMastered) return Colors.amber;
    if (s.roundCleared) return Colors.greenAccent;
    return Colors.white70;
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _FeedbackDisplay extends StatelessWidget {
  final AnswerResult? result;
  const _FeedbackDisplay({required this.result});

  @override
  Widget build(BuildContext context) {
    if (result == null) return const SizedBox(height: 40);
    final isCorrect = result == AnswerResult.correct;
    return SizedBox(
      height: 40,
      child: Text(
        isCorrect ? '✓' : '✗',
        style: TextStyle(
          fontSize: 32,
          color: isCorrect ? Colors.green : Colors.red,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _PlayButton extends StatefulWidget {
  final VoidCallback onPlay;
  final bool pulsing;
  const _PlayButton({required this.onPlay, required this.pulsing});

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(_PlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !oldWidget.pulsing) {
      _controller.forward();
    } else if (!widget.pulsing && oldWidget.pulsing) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 80.0;
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => widget.onPlay(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.pulsing
                ? [BoxShadow(color: Colors.white.withValues(alpha: 0.9), blurRadius: 24, spreadRadius: 8)]
                : [],
          ),
          child: CustomPaint(
            painter: _HexFillPainter(Colors.white),
            child: const Center(
              child: Icon(Icons.play_arrow, color: Colors.green, size: 36),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slot in the dynamic token grid.
class _TokenSlot {
  /// The NoteNugget from _chromaticScale (for display and GlobalKey lookup).
  final NoteNugget gridNugget;
  /// Whether a level note occupies this slot.
  final bool isActive;
  /// Horizontal alignment: -1 = left, 0 = center, 1 = right.
  int side = 0;

  _TokenSlot({required this.gridNugget, required this.isActive});
}

class _TokenGrid extends StatelessWidget {
  final LevelSpecs levelSpecs;
  final Mode mode;
  final NoteNugget? glowingNugget;
  final NoteNugget? wrongNugget;
  final Map<NoteNugget, GlobalKey> tokenKeys;
  final void Function(NoteNugget) onTap;
  final Widget playButton;

  const _TokenGrid({
    required this.levelSpecs,
    required this.mode,
    required this.glowingNugget,
    required this.wrongNugget,
    required this.tokenKeys,
    required this.onTap,
    required this.playButton,
  });

  /// Build a list of slots for [widestChromaticRange] chromatic positions,
  /// starting from the lowest available note. Each slot maps to a pitch class
  /// in _chromaticScale. Active slots have a level note; inactive are dimmed.
  List<_TokenSlot> _buildSlots() {
    final available = levelSpecs.availableNoteNuggets;

    // Absolute chromatic position = chromaticOffset + octave * 12
    int absPos(NoteNugget n) => n.getChromaticOffset(mode) + n.octave * 12;

    // Find the lowest absolute position among available notes.
    final activePositions = {for (final n in available) absPos(n)};
    final lowest = activePositions.reduce((a, b) => a < b ? a : b);

    final range = levelSpecs.widestChromaticRange;
    final slots = <_TokenSlot>[];

    for (int i = 0; i < range; i++) {
      final pos = lowest + i;
      final chromaticIndex = ((pos % 12) + 12) % 12; // always 0-11
      final gridNugget = _chromaticScale[chromaticIndex];
      slots.add(_TokenSlot(
        gridNugget: gridNugget,
        isActive: activePositions.contains(pos),
      ));
    }

    // Assign left/right/center using the original alternating algorithm:
    // toggle flips at each slot that has an active note;
    // first and last slots are always centered.
    int toggle = 1;
    for (int i = 0; i < slots.length; i++) {
      if (slots[i].isActive) toggle *= -1;
      if (i == 0 || i == slots.length - 1) {
        slots[i].side = 0; // centered
      } else {
        slots[i].side = toggle; // -1 left, +1 right
      }
    }

    return slots;
  }

  @override
  Widget build(BuildContext context) {
    final slots = _buildSlots();
    const tokenSize = 80.0;
    const rowHeight = tokenSize + 2.0;
    const gridWidth = tokenSize * 3.2;

    // Render top-to-bottom (slots are bottom-to-top, so reverse).
    final displaySlots = slots.reversed.toList();

    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: displaySlots.map((slot) {
            final alignment = slot.side == -1
                ? Alignment.centerLeft
                : slot.side == 1
                    ? Alignment.centerRight
                    : Alignment.center;
            return SizedBox(
              width: gridWidth,
              height: rowHeight,
              child: Align(
                alignment: alignment,
                child: _buildToken(slot, tokenSize),
              ),
            );
          }).toList(),
        ),
        playButton,
      ],
    );
  }

  Widget _buildToken(_TokenSlot slot, double size) {
    final nugget = slot.gridNugget;

    if (!slot.isActive) {
      // Ghost token: clear fill, white outline.
      return SizedBox(
        key: tokenKeys[nugget],
        width: size,
        height: size,
        child: CustomPaint(painter: _HexOutlinePainter()),
      );
    }

    final isGlowing = glowingNugget != null &&
        nugget.samePitchClass(glowingNugget!);
    final isWrong = wrongNugget != null &&
        nugget.samePitchClass(wrongNugget!);

    return AnimatedContainer(
      key: tokenKeys[nugget],
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: isWrong
            ? [BoxShadow(color: Colors.red.withValues(alpha: 0.85), blurRadius: 20, spreadRadius: 6)]
            : [],
      ),
      child: ToneToken(
        noteNugget: nugget,
        size: size,
        orientation: HexagonOrientation.flatTop,
        glowing: isGlowing,
        onTap: () => onTap(nugget),
      ),
    );
  }
}

/// Builds a flat-top hexagon path for the given size and inset ratio.
Path _hexPath(Size size, {double inset = 0.88}) {
  final cx = size.width / 2;
  final cy = size.height / 2;
  final r = size.width / 2 * inset;
  final path = Path();
  for (int i = 0; i < 6; i++) {
    final angle = (60.0 * i) * 3.14159265 / 180.0;
    final x = cx + r * cos(angle);
    final y = cy + r * sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

/// Draws a flat-top hexagon outline with a transparent fill.
class _HexOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(_hexPath(size), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Draws a flat-top hexagon filled with [color] and a white outline.
class _HexFillPainter extends CustomPainter {
  final Color color;
  _HexFillPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = _hexPath(size);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _HexFillPainter old) => old.color != color;
}

// ── Splash effect overlay ─────────────────────────────────────────────────────

class _SplashEffect extends StatefulWidget {
  final Offset center;
  final String label;
  final VoidCallback onDone;

  const _SplashEffect({
    required this.center,
    required this.label,
    required this.onDone,
  });

  @override
  State<_SplashEffect> createState() => _SplashEffectState();
}

class _SplashEffectState extends State<_SplashEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _rise;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(_controller);
    _rise = Tween<double>(begin: 0.0, end: 90.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Positioned(
          left: widget.center.dx - 40,
          top: widget.center.dy - 30 - _rise.value,
          width: 80,
          child: IgnorePointer(
            child: Opacity(
              opacity: _opacity.value,
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(offset: Offset(1, 2), blurRadius: 6, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Round end overlay ─────────────────────────────────────────────────────────

class _RoundEndOverlay extends StatelessWidget {
  final PracticeSession session;
  final VoidCallback onRestart;

  const _RoundEndOverlay({required this.session, required this.onRestart});

  @override
  Widget build(BuildContext context) {
    final mastered = session.roundMastered;
    final cleared = session.roundCleared;
    final specs = session.levelSpecs;

    final String headline = mastered
        ? 'MASTERED!'
        : cleared
            ? 'LEVEL CLEARED'
            : 'ROUND OVER';

    final Color headlineColor = mastered
        ? Colors.amber
        : cleared
            ? Colors.greenAccent
            : Colors.white70;

    final String sub = mastered
        ? 'Perfect — you\'ve mastered this level.'
        : cleared
            ? 'You\'re ready for the next level.'
            : 'Score ${session.totalPoints} — need ${specs.pointsToClear} to clear.';

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              headline,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: headlineColor,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              sub,
              style: const TextStyle(fontSize: 18, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${session.totalPoints} / ${specs.questionsPerRound * (specs.pointTiers.first)} pts',
              style: const TextStyle(fontSize: 16, color: Colors.white38),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTapDown: (_) => onRestart(),
              child: Container(
                width: 160,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(72),
                  border: Border.all(color: Colors.black, width: 2.5),
                ),
                child: const Icon(Icons.replay, color: Colors.green, size: 36),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
