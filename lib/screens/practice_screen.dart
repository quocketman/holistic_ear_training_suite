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
final _chromaticScale = [
  NoteNugget(scaleDegree: 1, chromaticAlteration: 0),
  NoteNugget(scaleDegree: 1, chromaticAlteration: 1),
  NoteNugget(scaleDegree: 2, chromaticAlteration: 0),
  NoteNugget(scaleDegree: 3, chromaticAlteration: -1),
  NoteNugget(scaleDegree: 3, chromaticAlteration: 0),
  NoteNugget(scaleDegree: 4, chromaticAlteration: 0),
  NoteNugget(scaleDegree: 4, chromaticAlteration: 1),
  NoteNugget(scaleDegree: 5, chromaticAlteration: 0),
  NoteNugget(scaleDegree: 6, chromaticAlteration: -1),
  NoteNugget(scaleDegree: 6, chromaticAlteration: 0),
  NoteNugget(scaleDegree: 7, chromaticAlteration: -1),
  NoteNugget(scaleDegree: 7, chromaticAlteration: 0),
];

/// Default level: diatonic major scale, single notes, random order.
final _defaultLevelSpecs = LevelSpecs(
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
          _session.nextQuestion();
          _playCurrentQuestion();
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

  void _onTokenTapped(NoteNugget nugget) {
    if (_sequencePlaying || _session.lastResult != null) return;

    final result = _session.submitAnswer(nugget);

    if (result == AnswerResult.correct) {
      if (widget.levelSpecs.answerTokensMakeASound) {
        final musicalState = context.read<MusicalState>();
        _audioService.playTone(musicalState.getMidiNote(nugget));
      }
      setState(() => _glowingNugget = nugget);
      _showSplash(nugget);
    } else {
      _playWrongSequence(nugget);
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
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      setState(() { _pulsing = false; _wrongNugget = wrongNugget; });
      _audioService.playTone(wrongMidi);
      await Future.delayed(const Duration(milliseconds: 300));
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
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _ScoreBar(session: session),
                  const SizedBox(height: 16),
                  _FeedbackDisplay(result: session.lastResult),
                  const Spacer(),
                  _PlayButton(onPlay: _startOrReplay, pulsing: _pulsing),
                  const Spacer(),
                  _TokenGrid(
                    activeNuggets: widget.levelSpecs.availableNoteNuggets,
                    glowingNugget: _glowingNugget,
                    wrongNugget: _wrongNugget,
                    tokenKeys: _tokenKeys,
                    onTap: _onTokenTapped,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _scoreChip(Icons.check_circle_outline, '${session.correctCount}', Colors.green),
        const SizedBox(width: 24),
        _scoreChip(Icons.cancel_outlined, '${session.incorrectCount}', Colors.red),
      ],
    );
  }

  Widget _scoreChip(IconData icon, String label, Color color) {
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
      duration: const Duration(milliseconds: 400),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_PlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !oldWidget.pulsing) {
      _controller.forward().then((_) => _controller.reverse());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => widget.onPlay(),
        child: Container(
          width: 160,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(72),
            border: Border.all(color: Colors.black, width: 2.5),
          ),
          child: const Icon(Icons.play_arrow, color: Colors.green, size: 36),
        ),
      ),
    );
  }
}

class _TokenGrid extends StatelessWidget {
  final List<NoteNugget> activeNuggets;
  final NoteNugget? glowingNugget;
  final NoteNugget? wrongNugget;
  final Map<NoteNugget, GlobalKey> tokenKeys;
  final void Function(NoteNugget) onTap;

  const _TokenGrid({
    required this.activeNuggets,
    required this.glowingNugget,
    required this.wrongNugget,
    required this.tokenKeys,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const tokenSize = 80.0;
    const spacing = 2.0;
    const verticalOffset = (tokenSize + spacing) / 2;

    final leftColumn = _chromaticScale.asMap().entries
        .where((e) => e.key % 2 == 0).toList().reversed.toList();
    final rightColumn = _chromaticScale.asMap().entries
        .where((e) => e.key % 2 == 1).toList().reversed.toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          children: leftColumn.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.0),
            child: _buildToken(e.value, tokenSize),
          )).toList(),
        ),
        const SizedBox(width: 1),
        Padding(
          padding: const EdgeInsets.only(bottom: verticalOffset),
          child: Column(
            children: rightColumn.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.0),
              child: _buildToken(e.value, tokenSize),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildToken(NoteNugget nugget, double size) {
    final isActive = activeNuggets.contains(nugget);
    final isGlowing = nugget == glowingNugget;
    final isWrong = nugget == wrongNugget;

    final List<BoxShadow> shadows = isGlowing
        ? [BoxShadow(color: Colors.yellow.withValues(alpha: 0.9), blurRadius: 24, spreadRadius: 8)]
        : isWrong
            ? [BoxShadow(color: Colors.red.withValues(alpha: 0.85), blurRadius: 20, spreadRadius: 6)]
            : [];

    return AnimatedContainer(
      key: tokenKeys[nugget],
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: shadows),
      child: Opacity(
        opacity: isActive ? 1.0 : 0.25,
        child: ToneToken(
          noteNugget: nugget,
          size: size,
          orientation: HexagonOrientation.flatTop,
          onTap: isActive ? () => onTap(nugget) : null,
        ),
      ),
    );
  }
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
