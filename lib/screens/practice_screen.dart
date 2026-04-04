import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_nugget.dart';
import '../models/level_specs.dart';
import '../models/musical_state.dart';
import '../models/practice_session.dart';
import '../models/tone_token_colors.dart';
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
  final List<LevelSpecs>? allLevels;
  final int? currentLevelIndex;

  PracticeScreen({
    super.key,
    LevelSpecs? levelSpecs,
    this.allLevels,
    this.currentLevelIndex,
  }) : levelSpecs = levelSpecs ?? _defaultLevelSpecs;

  LevelSpecs? get nextLevelSpecs {
    if (allLevels != null && currentLevelIndex != null &&
        currentLevelIndex! + 1 < allLevels!.length) {
      return allLevels![currentLevelIndex! + 1];
    }
    return null;
  }

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final AudioService _audioService = AudioService();
  late final PracticeSession _session;
  bool _pulsing = false;
  bool _sessionStarted = false;
  bool _roundActive = false;
  bool _sequencePlaying = false;
  bool _showRoundEnd = false;
  NoteNugget? _glowingNugget;
  NoteNugget? _wrongNugget;
  OverlayEntry? _splashEntry;
  bool _hideQuestionPoints = false;
  final GlobalKey _playButtonKey = GlobalKey();

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
          } else if (widget.levelSpecs.levelType == LevelType.warmUp) {
            // Warm-ups loop — restart the series automatically.
            _session.restart();
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

  Color get _questionTokenColor {
    if (!_roundActive || widget.levelSpecs.levelType != LevelType.warmUp) {
      return Colors.white;
    }
    final question = _session.currentQuestion;
    if (question == null) return Colors.white;
    final mode = context.read<MusicalState>().currentMode;
    return ToneTokenColors.getColor(question.getChromaticOffset(mode));
  }

  void _startOrReplay() {
    if (!_sessionStarted) {
      setState(() {
        _sessionStarted = true;
        _roundActive = true;
      });
    }
    _playCurrentQuestion();
  }

  Future<void> _playCurrentQuestion() async {
    final question = _session.currentQuestion;
    if (question == null) return;
    final musicalState = context.read<MusicalState>();
    final midiNote = musicalState.getMidiNote(question);
    setState(() { _pulsing = true; _hideQuestionPoints = false; });
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

    // Before round begins, just let the user explore the sounds.
    if (!_roundActive) {
      final musicalState = context.read<MusicalState>();
      _audioService.playTone(musicalState.getMidiNote(levelNugget));
      return;
    }

    final pointsBeforeAnswer = _session.currentQuestionPoints;
    final result = _session.submitAnswer(levelNugget);

    if (result == AnswerResult.correct) {
      if (widget.levelSpecs.answerTokensMakeASound) {
        final musicalState = context.read<MusicalState>();
        _audioService.playTone(musicalState.getMidiNote(levelNugget));
      }
      setState(() {
        _glowingNugget = levelNugget;
        _hideQuestionPoints = true;
      });
      if (widget.levelSpecs.levelType == LevelType.warmUp) {
        _flyHexToToken(gridNugget);
      } else {
        _flyPointsToToken(gridNugget, pointsBeforeAnswer);
      }
    } else {
      _playWrongSequence(levelNugget);
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

  void _flyPointsToToken(NoteNugget nugget, int points) {
    final playBox = _playButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (playBox == null) return;
    final playPos = playBox.localToGlobal(Offset.zero);
    final playSize = playBox.size;
    final from = Offset(playPos.dx + playSize.width / 2, playPos.dy + playSize.height / 2);

    final tokenKey = _tokenKeys[nugget];
    if (tokenKey == null) return;
    final tokenBox = tokenKey.currentContext?.findRenderObject() as RenderBox?;
    if (tokenBox == null) return;
    final tokenPos = tokenBox.localToGlobal(Offset.zero);
    final tokenSize = tokenBox.size;
    final to = Offset(tokenPos.dx + tokenSize.width / 2, tokenPos.dy + tokenSize.height / 2);

    final mode = context.read<MusicalState>().currentMode;
    final color = ToneTokenColors.getColor(nugget.getChromaticOffset(mode));

    _splashEntry?.remove();
    _splashEntry = OverlayEntry(
      builder: (_) => _HexFlyEffect(
        from: from,
        to: to,
        color: color,
        size: 80.0,
        label: '+$points',
        onDone: () {
          _splashEntry?.remove();
          _splashEntry = null;
        },
      ),
    );
    Overlay.of(context).insert(_splashEntry!);
  }

  void _flyHexToToken(NoteNugget nugget) {
    final playBox = _playButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (playBox == null) return;
    final playPos = playBox.localToGlobal(Offset.zero);
    final playSize = playBox.size;
    final from = Offset(playPos.dx + playSize.width / 2, playPos.dy + playSize.height / 2);

    final tokenKey = _tokenKeys[nugget];
    if (tokenKey == null) return;
    final tokenBox = tokenKey.currentContext?.findRenderObject() as RenderBox?;
    if (tokenBox == null) return;
    final tokenPos = tokenBox.localToGlobal(Offset.zero);
    final tokenSize = tokenBox.size;
    final to = Offset(tokenPos.dx + tokenSize.width / 2, tokenPos.dy + tokenSize.height / 2);

    final color = _questionTokenColor;

    _splashEntry?.remove();
    _splashEntry = OverlayEntry(
      builder: (_) => _HexFlyEffect(
        from: from,
        to: to,
        color: color,
        size: 80.0,
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
                      if (widget.levelSpecs.levelType == LevelType.warmUp)
                        Center(
                          child: _WarmUpNextButton(onNextLevel: () {
                            final next = widget.nextLevelSpecs;
                            if (next != null) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => PracticeScreen(
                                    levelSpecs: next,
                                    allLevels: widget.allLevels,
                                    currentLevelIndex: widget.currentLevelIndex! + 1,
                                  ),
                                ),
                              );
                            } else {
                              Navigator.of(context).pop();
                            }
                          }),
                        )
                      else
                        _ScoreBar(session: session),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _TokenGrid(
                          levelSpecs: widget.levelSpecs,
                          mode: context.read<MusicalState>().currentMode,
                          glowingNugget: _glowingNugget,
                          wrongNugget: _wrongNugget,
                          tokenKeys: _tokenKeys,
                          onTap: _onTokenTapped,
                          playButton: _PlayButton(
                            key: _playButtonKey,
                            onPlay: _startOrReplay,
                            pulsing: _pulsing,
                            showIcon: !_roundActive,
                            color: _questionTokenColor,
                            pointValue: _roundActive && !_hideQuestionPoints && widget.levelSpecs.levelType != LevelType.warmUp ? _session.currentQuestionPoints : null,
                          ),
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
                      _roundActive = false;
                      _session.restart();
                    }),
                    onNextLevel: () {
                      final next = widget.nextLevelSpecs;
                      if (next != null) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => PracticeScreen(
                                    levelSpecs: next,
                                    allLevels: widget.allLevels,
                                    currentLevelIndex: widget.currentLevelIndex! + 1,
                                  ),
                          ),
                        );
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
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

class _WarmUpNextButton extends StatelessWidget {
  final VoidCallback onNextLevel;
  const _WarmUpNextButton({required this.onNextLevel});

  @override
  Widget build(BuildContext context) {
    const size = 60.0;
    return GestureDetector(
      onTapDown: (_) => onNextLevel(),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _HexFillPainter(ToneTokenColors.faColor),
          child: const Center(
            child: Icon(Icons.arrow_forward, color: Colors.black87, size: 28),
          ),
        ),
      ),
    );
  }
}

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
    if (s.roundCleared) return ToneTokenColors.faColor;
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


class _PlayButton extends StatefulWidget {
  final VoidCallback onPlay;
  final bool pulsing;
  final bool showIcon;
  final Color color;
  final int? pointValue;
  const _PlayButton({super.key, required this.onPlay, required this.pulsing, this.showIcon = true, this.color = Colors.white, this.pointValue});

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
            painter: _HexFillPainter(widget.color),
            child: Center(
              child: widget.showIcon
                  ? Icon(Icons.play_arrow, color: ToneTokenColors.faColor, size: 36)
                  : widget.pointValue != null
                      ? Text(
                          '${widget.pointValue}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        )
                      : const SizedBox.shrink(),
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
        outlineOnly: !levelSpecs.answerTokensMakeASound,
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

class _PointsFlyEffect extends StatefulWidget {
  final Offset from;
  final Offset to;
  final String label;
  final VoidCallback onDone;

  const _PointsFlyEffect({
    required this.from,
    required this.to,
    required this.label,
    required this.onDone,
  });

  @override
  State<_PointsFlyEffect> createState() => _PointsFlyEffectState();
}

class _PointsFlyEffectState extends State<_PointsFlyEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
    _position = Tween<Offset>(begin: widget.from, end: widget.to).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
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
          left: _position.value.dx - 40,
          top: _position.value.dy - 18,
          width: 80,
          child: IgnorePointer(
            child: Opacity(
              opacity: _opacity.value,
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
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

class _HexFlyEffect extends StatefulWidget {
  final Offset from;
  final Offset to;
  final Color color;
  final double size;
  final String? label;
  final VoidCallback onDone;

  const _HexFlyEffect({
    required this.from,
    required this.to,
    required this.color,
    required this.size,
    this.label,
    required this.onDone,
  });

  @override
  State<_HexFlyEffect> createState() => _HexFlyEffectState();
}

class _HexFlyEffectState extends State<_HexFlyEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 30),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
    _position = Tween<Offset>(begin: widget.from, end: widget.to).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
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
        final s = widget.size * _scale.value;
        return Positioned(
          left: _position.value.dx - s / 2,
          top: _position.value.dy - s / 2,
          width: s,
          height: s,
          child: IgnorePointer(
            child: Opacity(
              opacity: _opacity.value,
              child: CustomPaint(
                painter: _HexFillPainter(widget.color),
                child: widget.label != null
                    ? Center(
                        child: Text(
                          widget.label!,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black45),
                            ],
                          ),
                        ),
                      )
                    : null,
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
  final VoidCallback onNextLevel;

  const _RoundEndOverlay({
    required this.session,
    required this.onRestart,
    required this.onNextLevel,
  });

  @override
  Widget build(BuildContext context) {
    final mastered = session.roundMastered;
    final cleared = session.roundCleared;
    final specs = session.levelSpecs;
    final isWarmUp = specs.levelType == LevelType.warmUp;

    final String headline = isWarmUp
        ? 'WARM-UP COMPLETE'
        : mastered
            ? 'MASTERED!'
            : cleared
                ? 'LEVEL CLEARED'
                : 'ROUND OVER';

    final Color headlineColor = isWarmUp
        ? Colors.amber
        : mastered
            ? Colors.amber
            : cleared
                ? ToneTokenColors.faColor
                : Colors.white70;

    final String sub = isWarmUp
        ? 'Ready to move on?'
        : mastered
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
            if (!isWarmUp) ...[
              const SizedBox(height: 8),
              Text(
                '${session.totalPoints} / ${specs.questionsPerRound * (specs.pointTiers.first)} pts',
                style: const TextStyle(fontSize: 16, color: Colors.white38),
              ),
            ],
            const SizedBox(height: 40),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _hexButton(Icons.replay, Colors.white, onRestart),
                const SizedBox(width: 24),
                _hexButton(Icons.arrow_forward, ToneTokenColors.faColor, onNextLevel),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hexButton(IconData icon, Color color, VoidCallback onTap) {
    const size = 80.0;
    return GestureDetector(
      onTapDown: (_) => onTap(),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _HexFillPainter(color),
          child: Center(
            child: Icon(icon, color: Colors.black87, size: 36),
          ),
        ),
      ),
    );
  }
}
