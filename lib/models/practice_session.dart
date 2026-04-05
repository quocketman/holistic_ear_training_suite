import 'package:flutter/foundation.dart';
import 'note_nugget.dart';
import 'level_specs.dart';
import 'note_nugget_dispenser.dart';
import 'musical_state.dart';

/// The result of a single answer tap.
enum AnswerResult { correct, incorrect }

/// Runs a single practice session driven by a [LevelSpecs].
/// Owns the dispenser, tracks the current question, and evaluates answers.
/// Extends ChangeNotifier so the UI can rebuild on state changes.
class PracticeSession extends ChangeNotifier {
  final LevelSpecs levelSpecs;
  final MusicalState musicalState;
  final NoteNuggetDispenser _dispenser;

  NoteNugget? _currentQuestion;
  NoteNugget? _lastQuestion;
  AnswerResult? _lastResult;

  /// For inARow > 1: the full sequence of notes to identify.
  List<NoteNugget> _currentSequence = [];

  /// Index of the next note the player must tap in the sequence.
  int _sequencePosition = 0;

  /// Colors filled in as the player answers correctly.
  /// Length == inARow; null entries = not yet answered.
  List<NoteNugget?> _sequenceAnswered = [];

  /// Whether there were any wrong taps during this sequence.
  bool _hadSequenceErrors = false;

  int _correctCount = 0;
  int _incorrectCount = 0;
  int _wrongAttemptsOnCurrentQuestion = 0;
  int _questionsAnswered = 0;
  int _totalPoints = 0;
  int _seriesIndex = 0;

  PracticeSession({
    required this.levelSpecs,
    required this.musicalState,
  }) : _dispenser = NoteNuggetDispenser(levelSpecs: levelSpecs);

  // ── Getters ─────────────────────────────────────────────────────────────────

  /// The nugget the user is currently being asked to identify. Null before
  /// the first call to [nextQuestion]. For sequences, this is the note at
  /// [_sequencePosition].
  NoteNugget? get currentQuestion => _currentQuestion;

  /// Result of the most recent answer tap.
  AnswerResult? get lastResult => _lastResult;

  /// How many notes in a row the player must identify per question.
  int get inARow => levelSpecs.howManyInARow;

  /// The full sequence of notes for the current question (length == inARow).
  List<NoteNugget> get currentSequence => List.unmodifiable(_currentSequence);

  /// Which notes have been correctly answered so far (null = not yet answered).
  List<NoteNugget?> get sequenceAnswered => List.unmodifiable(_sequenceAnswered);

  /// Index of the next note the player needs to tap.
  int get sequencePosition => _sequencePosition;

  /// Whether the player has completed the current sequence.
  bool get sequenceComplete => _sequencePosition >= _currentSequence.length;

  int get correctCount => _correctCount;
  int get incorrectCount => _incorrectCount;
  int get totalAnswered => _correctCount + _incorrectCount;
  int get totalPoints => _totalPoints;
  int get questionsAnswered => _questionsAnswered;

  /// Whether all questions in the round have been answered.
  bool get roundComplete {
    final series = levelSpecs.simpleNuggetSeries;
    if (series != null &&
        levelSpecs.puzzleGenerationMethod == PuzzleGenerationMethod.seriesForwardOnly) {
      return _seriesIndex >= series.length;
    }
    return _questionsAnswered >= levelSpecs.questionsPerRound;
  }

  /// Whether the player has cleared the level (may progress).
  bool get roundCleared => _totalPoints >= levelSpecs.pointsToClear;

  /// Whether the player has mastered the level (full recognition).
  bool get roundMastered => _totalPoints >= levelSpecs.pointsToMaster;

  /// How many wrong taps have been made on the current question.
  /// Resets when [nextQuestion] is called.
  int get wrongAttemptsOnCurrentQuestion => _wrongAttemptsOnCurrentQuestion;

  /// Points the current question is worth given wrong attempts so far.
  int get currentQuestionPoints {
    final tiers = levelSpecs.pointTiers;
    final index = _wrongAttemptsOnCurrentQuestion.clamp(0, tiers.length - 1);
    return tiers[index];
  }

  // ── Session control ─────────────────────────────────────────────────────────

  /// Picks the next question (or sequence of questions) and notifies listeners.
  void nextQuestion() {
    if (roundComplete) return;
    _lastResult = null;
    _wrongAttemptsOnCurrentQuestion = 0;
    _hadSequenceErrors = false;
    _sequencePosition = 0;

    // Generate the sequence (length == inARow).
    _currentSequence = [];
    for (int i = 0; i < inARow; i++) {
      final nugget = _pickNextNugget();
      if (nugget != null) _currentSequence.add(nugget);
    }
    _sequenceAnswered = List.filled(_currentSequence.length, null);

    // currentQuestion points to the first note the player needs to identify.
    _currentQuestion = _currentSequence.isNotEmpty ? _currentSequence[0] : null;
    notifyListeners();
  }

  /// Call when the user taps a [ToneToken]. Returns the result and
  /// updates counts, then notifies listeners.
  ///
  /// For sequences (inARow > 1), a correct tap advances to the next note.
  /// The sequence is "complete" when all notes are answered. Points are
  /// awarded once for the whole sequence based on wrong attempts.
  AnswerResult submitAnswer(NoteNugget tappedNugget) {
    if (tappedNugget == _currentQuestion) {
      _lastResult = AnswerResult.correct;

      // Record this note in the answered list.
      if (_sequencePosition < _sequenceAnswered.length) {
        _sequenceAnswered[_sequencePosition] = tappedNugget;
      }

      _sequencePosition++;

      if (_sequencePosition < _currentSequence.length) {
        // More notes to go — advance currentQuestion.
        _currentQuestion = _currentSequence[_sequencePosition];
      } else {
        // Sequence complete — award points for the whole sequence.
        _correctCount++;
        _questionsAnswered++;
        if (levelSpecs.levelType != LevelType.warmUp) {
          _totalPoints += _pointsForCurrentQuestion();
        }
      }

      notifyListeners();
      return AnswerResult.correct;
    } else {
      _wrongAttemptsOnCurrentQuestion++;
      _hadSequenceErrors = true;
      _incorrectCount++;
      notifyListeners();
      return AnswerResult.incorrect;
    }
  }

  /// Points awarded for the current question based on wrong attempts so far.
  int _pointsForCurrentQuestion() {
    final tiers = levelSpecs.pointTiers;
    final index = _wrongAttemptsOnCurrentQuestion.clamp(0, tiers.length - 1);
    return tiers[index];
  }

  /// Resets counts and picks a fresh first question.
  void restart() {
    _correctCount = 0;
    _incorrectCount = 0;
    _totalPoints = 0;
    _questionsAnswered = 0;
    _lastResult = null;
    _lastQuestion = null;
    _currentQuestion = null;
    _currentSequence = [];
    _sequenceAnswered = [];
    _sequencePosition = 0;
    _hadSequenceErrors = false;
    _seriesIndex = 0;
    _dispenser.resetIndex();
    nextQuestion();
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  NoteNugget? _pickNextNugget() {
    if (_dispenser.isEmpty) return null;

    // Always start with the preferred first note if this is the opening question
    // (unless a simpleNuggetSeries already defines the sequence).
    if (_lastQuestion == null &&
        levelSpecs.preferredFirstNote != null &&
        levelSpecs.simpleNuggetSeries == null) {
      _lastQuestion = levelSpecs.preferredFirstNote;
      return levelSpecs.preferredFirstNote;
    }

    NoteNugget? candidate;

    // Series-based levels should not retry — the sequence is fixed.
    if (levelSpecs.simpleNuggetSeries != null) {
      candidate = _selectByMethod();
    } else {
      int attempts = 0;
      const maxAttempts = 10;
      do {
        candidate = _selectByMethod();
        attempts++;
      } while (
        levelSpecs.noTwiceInARow &&
        candidate == _lastQuestion &&
        attempts < maxAttempts
      );
    }

    _lastQuestion = candidate;
    return candidate;
  }

  NoteNugget? _selectByMethod() {
    switch (levelSpecs.puzzleGenerationMethod) {
      case PuzzleGenerationMethod.random:
        return _dispenser.randomNoteNugget;

      case PuzzleGenerationMethod.seriesForwardOnly:
        final series = levelSpecs.simpleNuggetSeries;
        if (series != null) {
          if (_seriesIndex >= series.length) return null;
          final degree = series[_seriesIndex];
          _seriesIndex++;
          return levelSpecs.availableNoteNuggets
              .firstWhere((n) => n.scaleDegree == degree);
        }
        return _dispenser.nextNoteNugget;

      case PuzzleGenerationMethod.seriesForwardAndBack:
        return _dispenser.nextPreviousOrCurrentNoteNugget;

      // Placeholder — will be replaced with a real probability engine later.
      case PuzzleGenerationMethod.shiftingProbabilities:
      case PuzzleGenerationMethod.playCountBasedProbabilities:
        return _dispenser.randomNoteNugget;
    }
  }
}
