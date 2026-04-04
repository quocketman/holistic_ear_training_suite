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
  /// the first call to [nextQuestion].
  NoteNugget? get currentQuestion => _currentQuestion;

  /// Result of the most recent answer tap.
  AnswerResult? get lastResult => _lastResult;

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

  /// Picks the next question nugget and notifies listeners.
  /// Respects [LevelSpecs.noTwiceInARow] and [LevelSpecs.puzzleGenerationMethod].
  void nextQuestion() {
    if (roundComplete) return;
    _lastResult = null;
    _wrongAttemptsOnCurrentQuestion = 0;
    _currentQuestion = _pickNextNugget();
    notifyListeners();
  }

  /// Call when the user taps a [ToneToken]. Returns the result and
  /// updates counts, then notifies listeners.
  AnswerResult submitAnswer(NoteNugget tappedNugget) {
    if (tappedNugget == _currentQuestion) {
      _lastResult = AnswerResult.correct;
      _correctCount++;
      _questionsAnswered++;
      if (levelSpecs.levelType != LevelType.warmUp) {
        _totalPoints += _pointsForCurrentQuestion();
      }
      notifyListeners();
      return AnswerResult.correct;
    } else {
      _wrongAttemptsOnCurrentQuestion++;
      _incorrectCount++;
      // lastResult stays null — wrong answers don't lock the session.
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
