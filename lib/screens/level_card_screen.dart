import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/hex_grid_cell.dart';
import '../models/enums.dart';
import '../models/level_specs.dart';
import '../models/note_nugget.dart';
import '../models/musical_state.dart';
import '../models/practice_session.dart';
import '../models/tone_token_colors.dart';
import '../services/audio_service.dart';
import '../utils/hex_grid_builder.dart';
import '../utils/ladder_layout.dart';
import '../widgets/tone_token.dart';

/// Unified game board screen. Shows the ladder tokens inside a hex container,
/// sequence dots on top, and phase buttons below. Swipe left/right to change
/// in-a-row tier. Tapping a phase button starts a round.
class LevelCardScreen extends StatefulWidget {
  final List<HexGridCell> row;
  final int initialColumn;

  const LevelCardScreen({
    super.key,
    required this.row,
    required this.initialColumn,
  });

  @override
  State<LevelCardScreen> createState() => _LevelCardScreenState();
}

class _LevelCardScreenState extends State<LevelCardScreen> {
  late int _currentTier;
  late int _inARow;

  // ── Game state ──
  final AudioService _audioService = AudioService();
  PracticeSession? _session;
  bool _roundActive = false;
  bool _pulsing = false;
  bool _sequencePlaying = false;
  bool _listeningToSequence = false;
  int _activeSequenceIndex = -1;
  bool _showRoundEnd = false;
  NoteNugget? _glowingNugget;
  NoteNugget? _wrongNugget;
  OverlayEntry? _splashEntry;
  bool _hideQuestionPoints = false;
  final GlobalKey _playButtonKey = GlobalKey();
  int _generation = 0;
  bool _isPlayingQuestion = false;
  bool _advancePending = false;

  Map<NoteNugget, GlobalKey> _tokenKeys = {};
  List<LadderSlot> _ladderSlots = [];

  HexGridCell get _currentCell => widget.row[_currentTier];

  @override
  void initState() {
    super.initState();
    _currentTier = widget.initialColumn;
    _inARow = _currentTier + 1;
    _buildTokenKeys();
  }

  @override
  void dispose() {
    _splashEntry?.remove();
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
    _audioService.dispose();
    super.dispose();
  }

  void _buildTokenKeys() {
    final cell = _currentCell;
    final rep = cell.representativeLevel;
    if (rep == null) return;
    final mode = rep.preferredMode ?? Mode.major;
    _ladderSlots = buildLadderSlots(
      availableNotes: rep.availableNoteNuggets,
      mode: mode,
      widestChromaticRange: rep.widestChromaticRange,
    );
    _tokenKeys = {for (final s in _ladderSlots) s.nugget: GlobalKey()};
  }

  // ── Round lifecycle ──

  void _startRound(LevelSpecs level) {
    _generation++;
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();

    final musicalState = context.read<MusicalState>();
    _session = PracticeSession(levelSpecs: level, musicalState: musicalState);
    _session!.addListener(_onSessionChanged);
    _session!.nextQuestion();

    setState(() {
      _roundActive = true;
      _showRoundEnd = false;
      _advancePending = false;
      _isPlayingQuestion = false;
      _glowingNugget = null;
      _wrongNugget = null;
      _hideQuestionPoints = false;
      _listeningToSequence = false;
      _activeSequenceIndex = -1;
    });

    _playCurrentQuestion();
  }

  void _endRound() {
    _generation++;
    setState(() {
      _roundActive = false;
      _showRoundEnd = false;
      _advancePending = false;
      _isPlayingQuestion = false;
    });
    _session?.removeListener(_onSessionChanged);
  }

  // ── Session listener ──

  void _onSessionChanged() {
    if (_session == null) return;
    if (_session!.lastResult == AnswerResult.correct) {
      final gen = _generation;
      if (_session!.sequenceComplete && !_advancePending) {
        _advancePending = true;
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted || gen != _generation) return;
          setState(() => _glowingNugget = null);

          Future.delayed(const Duration(milliseconds: 600), () {
            if (!mounted || gen != _generation) return;
            _advancePending = false;
            _isPlayingQuestion = false;
            if (!_session!.roundComplete) {
              _session!.nextQuestion();
              _playCurrentQuestion();
            } else if (_session!.levelSpecs.levelType == LevelType.warmUp) {
              _session!.restart();
              _playCurrentQuestion();
            } else {
              Future.delayed(const Duration(milliseconds: 1000), () {
                if (mounted && gen == _generation) {
                  setState(() => _showRoundEnd = true);
                }
              });
            }
          });
        });
      } else if (!_session!.sequenceComplete) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && gen == _generation) {
            setState(() => _glowingNugget = null);
          }
        });
      }
    }
  }

  // ── Audio ──

  Future<void> _playCurrentQuestion() async {
    if (_isPlayingQuestion || _session == null) return;
    final sequence = _session!.currentSequence;
    if (sequence.isEmpty) return;
    _isPlayingQuestion = true;
    final musicalState = context.read<MusicalState>();

    setState(() {
      _pulsing = true;
      _hideQuestionPoints = false;
      _listeningToSequence = true;
    });

    for (int i = 0; i < sequence.length; i++) {
      if (!mounted) { _isPlayingQuestion = false; return; }
      final midiNote = musicalState.getMidiNote(sequence[i]);
      setState(() => _activeSequenceIndex = i);
      await _audioService.playTone(midiNote);
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (!mounted) { _isPlayingQuestion = false; return; }
    setState(() {
      _pulsing = false;
      _listeningToSequence = false;
      _activeSequenceIndex = -1;
    });
    _isPlayingQuestion = false;
  }

  void _replayQuestion() {
    if (_isPlayingQuestion) return;
    _playCurrentQuestion();
  }

  Future<void> _playWrongSequence(NoteNugget wrongNugget) async {
    if (_session == null) return;
    final question = _session!.currentQuestion;
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

  // ── Token tap ──

  NoteNugget? _resolveToLevelNugget(NoteNugget gridNugget) {
    final level = _currentCell.representativeLevel;
    if (level == null) return null;
    try {
      return level.availableNoteNuggets
          .firstWhere((n) => n.samePitchClass(gridNugget));
    } catch (_) {
      return null;
    }
  }

  void _onTokenTapped(NoteNugget gridNugget) {
    if (_sequencePlaying || _listeningToSequence) return;
    if (_session == null) return;
    if (_session!.lastResult != null && _session!.sequenceComplete) return;

    final levelNugget = _resolveToLevelNugget(gridNugget);
    if (levelNugget == null) return;

    if (!_roundActive) {
      // Explore mode — just play the sound.
      final musicalState = context.read<MusicalState>();
      _audioService.playTone(musicalState.getMidiNote(levelNugget));
      return;
    }

    final pointsBefore = _session!.currentQuestionPoints;
    final result = _session!.submitAnswer(levelNugget);

    if (result == AnswerResult.correct) {
      final level = _session!.levelSpecs;
      if (level.answerTokensMakeASound) {
        final musicalState = context.read<MusicalState>();
        _audioService.playTone(musicalState.getMidiNote(levelNugget));
      }
      setState(() {
        _glowingNugget = levelNugget;
        _hideQuestionPoints = true;
      });
      if (level.levelType == LevelType.warmUp) {
        _flyHexToToken(gridNugget);
      } else {
        _flyPointsToToken(gridNugget, pointsBefore);
      }
    } else {
      _playWrongSequence(levelNugget);
    }
  }

  // ── Fly animations ──

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
        from: from, to: to, color: color, size: 60.0,
        label: '+$points',
        onDone: () { _splashEntry?.remove(); _splashEntry = null; },
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

    final mode = context.read<MusicalState>().currentMode;
    final color = ToneTokenColors.getColor(nugget.getChromaticOffset(mode));

    _splashEntry?.remove();
    _splashEntry = OverlayEntry(
      builder: (_) => _HexFlyEffect(
        from: from, to: to, color: color, size: 60.0,
        onDone: () { _splashEntry?.remove(); _splashEntry = null; },
      ),
    );
    Overlay.of(context).insert(_splashEntry!);
  }

  Color get _questionTokenColor {
    if (!_roundActive || _session == null) return Colors.white;
    if (_session!.levelSpecs.levelType != LevelType.warmUp) return Colors.white;
    final question = _session!.currentQuestion;
    if (question == null) return Colors.white;
    final mode = context.read<MusicalState>().currentMode;
    return ToneTokenColors.getColor(question.getChromaticOffset(mode));
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final cell = _currentCell;
    final label = cell.displayLabel;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _roundActive && _session != null
              ? _session!.levelSpecs.levelTitle
              : '$label  ×$_inARow',
        ),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: _roundActive ? null : _onSwipe,
        child: Column(
          children: [
            _buildScoreBar(),
            Expanded(child: _buildGameBoard()),
            // Bottom area — fixed height so hex doesn't shift.
            SizedBox(
              height: 100,
              child: !_roundActive
                  ? _buildPhaseButtons()
                  : _showRoundEnd
                      ? _buildRoundEndBar()
                      : const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 8),
              child: _buildTierDots(),
            ),
          ],
        ),
      ),
    );
  }

  void _onSwipe(DragEndDetails details) {
    if (_roundActive) return;
    final dx = details.velocity.pixelsPerSecond.dx;
    if (dx < -200 && _currentTier < hexGridColumns - 1) {
      setState(() {
        _currentTier++;
        _inARow = _currentTier + 1;
        _buildTokenKeys();
      });
    } else if (dx > 200 && _currentTier > 0) {
      setState(() {
        _currentTier--;
        _inARow = _currentTier + 1;
        _buildTokenKeys();
      });
    }
  }

  Widget _buildTierDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(hexGridColumns, (i) {
        final tierCell = widget.row[i];
        final isCurrent = i == _currentTier;
        return GestureDetector(
          onTap: _roundActive ? null : () {
            setState(() {
              _currentTier = i;
              _inARow = i + 1;
              _buildTokenKeys();
            });
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: isCurrent ? 12 : 10,
            height: isCurrent ? 12 : 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? Colors.white
                  : tierCell.hasLevels
                      ? Colors.white24
                      : Colors.white10,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildScoreBar() {
    // Always reserve the same height so the hex doesn't shift.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SizedBox(
        height: 24,
        child: _roundActive && _session != null && _session!.levelSpecs.levelType != LevelType.warmUp
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.music_note, color: Colors.white70, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '${_session!.questionsAnswered}/${_session!.levelSpecs.questionsPerRound}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                  const SizedBox(width: 20),
                  const Icon(Icons.star_outline, color: Colors.white70, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '${_session!.totalPoints}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _session!.roundMastered ? Colors.amber
                          : _session!.roundCleared ? ToneTokenColors.faColor
                          : Colors.white70,
                    ),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildGameBoard() {
    final cell = _currentCell;
    final rep = cell.representativeLevel;
    if (rep == null || !cell.hasLevels) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text('Coming soon', style: TextStyle(color: Colors.white24, fontSize: 16)),
          ],
        ),
      );
    }

    final mode = rep.preferredMode ?? Mode.major;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth * 0.88;
        final maxHeight = constraints.maxHeight * 0.95;
        // Flat-top hex: height = width * sqrt(3)/2
        final hexWidth = min(maxWidth, maxHeight / 0.866);
        final hexHeight = hexWidth * 0.866;

        // Calculate token size from hex interior and semitone count.
        final totalSemitones = _ladderSlots.isNotEmpty
            ? _ladderSlots.last.semitoneFromBottom
            : 1;
        final usableHeight = hexHeight * 0.70; // interior area
        final tokenSize = min(
          usableHeight / (1 + totalSemitones),
          hexWidth * 0.28,
        );

        final gridSize = Size(hexWidth * 0.70, usableHeight);
        final positions = positionsForSlots(
          slots: _ladderSlots,
          size: gridSize,
          tokenSize: tokenSize,
        );

        final gridOffsetX = (hexWidth - gridSize.width) / 2;
        final gridOffsetY = hexHeight * 0.12;

        return Center(
          child: SizedBox(
            width: hexWidth,
            height: hexHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Hex container.
                CustomPaint(
                  painter: _HexContainerPainter(),
                  child: const SizedBox.expand(),
                ),
                // Sequence tokens on top of hex.
                Positioned(
                  top: -20,
                  left: 0,
                  right: 0,
                  child: _buildSequenceTokens(),
                ),
                // Ladder tokens.
                for (int i = 0; i < _ladderSlots.length; i++)
                  Positioned(
                    left: gridOffsetX + positions[i].dx - tokenSize / 2,
                    top: gridOffsetY + positions[i].dy - tokenSize / 2,
                    width: tokenSize,
                    height: tokenSize,
                    child: _buildToken(_ladderSlots[i], tokenSize, mode),
                  ),
                // Question token (play button) in center.
                Positioned.fill(
                  child: Center(
                    child: _buildQuestionToken(tokenSize),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSequenceTokens() {
    final count = _session != null ? _session!.inARow : _inARow;
    final answered = _session?.sequenceAnswered;
    final mode = context.read<MusicalState>().currentMode;
    const hexSize = 28.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        Color fillColor;
        if (answered != null && i < answered.length && answered[i] != null) {
          fillColor = ToneTokenColors.getColor(answered[i]!.getChromaticOffset(mode));
        } else {
          fillColor = Colors.white;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(
            width: hexSize,
            height: hexSize,
            child: CustomPaint(painter: _HexFillPainter(fillColor)),
          ),
        );
      }),
    );
  }

  Widget _buildToken(LadderSlot slot, double size, Mode mode) {
    if (!slot.isActive) {
      return SizedBox(
        key: _tokenKeys[slot.nugget],
        width: size,
        height: size,
        child: CustomPaint(painter: _HexOutlinePainter()),
      );
    }

    final nugget = slot.nugget;
    final isGlowing = _glowingNugget != null && nugget.samePitchClass(_glowingNugget!);
    final isWrong = _wrongNugget != null && nugget.samePitchClass(_wrongNugget!);
    final dimmed = _listeningToSequence;
    final level = _currentCell.representativeLevel;
    final outlineOnly = level != null && !level.answerTokensMakeASound;

    return Opacity(
      opacity: dimmed ? 0.3 : 1.0,
      child: AnimatedContainer(
        key: _tokenKeys[nugget],
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
          outlineOnly: outlineOnly,
          onTap: () => _onTokenTapped(nugget),
        ),
      ),
    );
  }

  Widget _buildQuestionToken(double tokenSize) {
    final qSize = tokenSize * 0.9;
    return GestureDetector(
      key: _playButtonKey,
      onTapDown: (_) {
        if (_roundActive) {
          _replayQuestion();
        }
      },
      child: SizedBox(
        width: qSize,
        height: qSize,
        child: CustomPaint(
          painter: _HexFillPainter(_questionTokenColor),
          child: _roundActive && !_hideQuestionPoints && _session != null &&
              _session!.levelSpecs.levelType != LevelType.warmUp
              ? Center(
                  child: Text(
                    '${_session!.currentQuestionPoints}',
                    style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildPhaseButtons() {
    final cell = _currentCell;
    if (!cell.hasLevels || !cell.isUnlocked) return const SizedBox(height: 80);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (cell.warmUpLevel != null)
            _phaseButton(
              fillColor: ToneTokenColors.faColor,
              outlineColor: Colors.white,
              label: 'Warm-up',
              locked: false,
              onTap: () => _startRound(cell.warmUpLevel!),
            ),
          if (cell.practiceLevel != null)
            _phaseButton(
              fillColor: Colors.white,
              outlineColor: Colors.lightBlueAccent,
              iconColor: Colors.black87,
              label: 'Practice',
              locked: false,
              onTap: () => _startRound(cell.practiceLevel!),
            ),
          if (cell.challengeLevel != null)
            _phaseButton(
              fillColor: Colors.black,
              outlineColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              label: 'Challenge',
              locked: !cell.practiceCleared,
              onTap: cell.practiceCleared
                  ? () => _startRound(cell.challengeLevel!)
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _phaseButton({
    required Color fillColor,
    required Color outlineColor,
    Color iconColor = Colors.white,
    required String label,
    required bool locked,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CustomPaint(
              painter: _HexButtonPainter(
                fillColor: locked ? Colors.black : fillColor,
                outlineColor: locked ? Colors.white24 : outlineColor,
              ),
              child: Center(
                child: locked
                    ? const Icon(Icons.lock_outline, color: Colors.white24, size: 20)
                    : Icon(Icons.play_arrow, color: iconColor, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
            fontSize: 9,
            color: locked ? Colors.white24 : Colors.white54,
          )),
        ],
      ),
    );
  }

  Widget _buildRoundEndBar() {
    if (_session == null) return const SizedBox.shrink();
    final mastered = _session!.roundMastered;
    final cleared = _session!.roundCleared;

    final headline = mastered ? 'MASTERED!' : cleared ? 'CLEARED' : 'ROUND OVER';
    final color = mastered ? Colors.amber : cleared ? ToneTokenColors.faColor : Colors.white70;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        children: [
          Text(headline, style: TextStyle(
            fontSize: 28, fontWeight: FontWeight.bold, color: color, letterSpacing: 2,
          )),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _phaseButton(
                fillColor: Colors.white,
                outlineColor: Colors.white54,
                iconColor: Colors.black87,
                label: 'Replay',
                locked: false,
                onTap: () => _startRound(_session!.levelSpecs),
              ),
              const SizedBox(width: 24),
              _phaseButton(
                fillColor: ToneTokenColors.faColor,
                outlineColor: Colors.white,
                label: 'Done',
                locked: false,
                onTap: _endRound,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Painters ─────────────────────────────────────────────────────────────────

Path _flatTopHexContainerPath(Size size, {double inset = 0.98}) {
  final cx = size.width / 2;
  final cy = size.height / 2;
  final r = size.width / 2 * inset;
  final path = Path();
  for (int i = 0; i < 6; i++) {
    final angle = (60.0 * i) * pi / 180.0;
    final x = cx + r * cos(angle);
    final y = cy + r * sin(angle);
    if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
  }
  path.close();
  return path;
}

class _HexContainerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _flatTopHexContainerPath(size);
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.05));
    canvas.drawPath(path, Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HexFillPainter extends CustomPainter {
  final Color color;
  _HexFillPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 * 0.88;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (60.0 * i) * pi / 180.0;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HexFillPainter old) => old.color != color;
}

class _HexOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 * 0.88;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (60.0 * i) * pi / 180.0;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(path, Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HexButtonPainter extends CustomPainter {
  final Color fillColor;
  final Color outlineColor;
  _HexButtonPainter({required this.fillColor, required this.outlineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 * 0.88;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (60.0 * i) * pi / 180.0;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(path, Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0);
  }

  @override
  bool shouldRepaint(covariant _HexButtonPainter old) =>
      old.fillColor != fillColor || old.outlineColor != outlineColor;
}

// ── Fly effect ───────────────────────────────────────────────────────────────

class _HexFlyEffect extends StatefulWidget {
  final Offset from;
  final Offset to;
  final Color color;
  final double size;
  final String? label;
  final VoidCallback onDone;

  const _HexFlyEffect({
    required this.from, required this.to, required this.color,
    required this.size, this.label, required this.onDone,
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 30),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
    _position = Tween<Offset>(begin: widget.from, end: widget.to)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _scale = Tween<double>(begin: 1.0, end: 0.6)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final s = widget.size * _scale.value;
        return Positioned(
          left: _position.value.dx - s / 2,
          top: _position.value.dy - s / 2,
          width: s, height: s,
          child: IgnorePointer(
            child: Opacity(
              opacity: _opacity.value,
              child: CustomPaint(
                painter: _HexFillPainter(widget.color),
                child: widget.label != null
                    ? Center(child: Text(widget.label!,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                          color: Colors.white, shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black45)])))
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
