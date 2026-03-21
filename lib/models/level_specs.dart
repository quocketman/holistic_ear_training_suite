import 'note_nugget.dart';
import 'enums.dart';

/// How the next question nugget is selected from the available set.
/// Mirrors LUPuzzleGenerationMethod.
enum PuzzleGenerationMethod {
  random,
  shiftingProbabilities,
  seriesForwardAndBack,
  seriesForwardOnly,
  playCountBasedProbabilities,
}

/// Broad category of a level, used for UI labeling and difficulty curves.
/// Mirrors LULevelType.
enum LevelType {
  freePlay,
  warmUp,
  practice,
  challenge,
  bonus,
}

/// Controls what the answer tokens display before the user taps.
/// Mirrors LUQuestionTokenSymbolMode.
enum QuestionTokenSymbolMode {
  blank,        // tokens show no label — hardest
  colorOnly,    // tokens show color only
  textAndColor, // tokens show solfège label and color — easiest
}

/// Specifies the rules and content for a single practice level.
/// Mirrors LULevelSpecs.
class LevelSpecs {
  final String levelTitle;

  /// The NoteNuggets available as both questions and answers in this level.
  final List<NoteNugget> availableNoteNuggets;

  /// How many notes sound simultaneously (1 = single note, >1 = chord).
  final int howManyAtATime;

  /// How many notes play in sequence before the user answers (1 = single, >1 = melodic memory).
  final int howManyInARow;

  /// Whether the same nugget can appear twice in a row.
  final bool noTwiceInARow;

  /// Tapping an answer token also plays its tone.
  final bool answerTokensMakeASound;

  /// How question nuggets are chosen from [availableNoteNuggets].
  final PuzzleGenerationMethod puzzleGenerationMethod;

  /// What the answer tokens display before the user taps.
  final QuestionTokenSymbolMode questionTokenSymbolMode;

  /// Preferred mode for this level (overrides global MusicalState when set).
  final Mode? preferredMode;

  /// Widest chromatic interval allowed between consecutive question notes.
  /// 0 means no restriction.
  final int widestChromaticRange;

  /// Optional instructional copy shown to the user.
  final String? instructiveText1;
  final String? instructiveText2;

  final LevelType levelType;

  /// If set, this nugget is always played as the very first question.
  /// Mirrors LULevelSpecs preferredFirstNote.
  final NoteNugget? preferredFirstNote;

  const LevelSpecs({
    required this.levelTitle,
    required this.availableNoteNuggets,
    this.howManyAtATime = 1,
    this.howManyInARow = 1,
    this.noTwiceInARow = false,
    this.answerTokensMakeASound = true,
    this.puzzleGenerationMethod = PuzzleGenerationMethod.random,
    this.questionTokenSymbolMode = QuestionTokenSymbolMode.textAndColor,
    this.preferredMode,
    this.widestChromaticRange = 0,
    this.instructiveText1,
    this.instructiveText2,
    this.levelType = LevelType.practice,
    this.preferredFirstNote,
  });
}
