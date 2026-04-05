import 'dart:convert';
import 'package:flutter/services.dart';
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
  /// Unique identifier used for progress tracking and JSON loading.
  final String id;

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

  /// Fixed sequence of scale degrees for seriesForwardOnly levels.
  /// Each entry is a scaleDegree (e.g. 1, 2, 7). The round ends when exhausted.
  final List<int>? simpleNuggetSeries;

  /// Pairs of scale degrees representing allowed melodic motions.
  /// e.g. [[1,2],[2,1]] means do→re and re→do are allowed.
  final List<List<int>> allowedMotions;

  // ── Round & scoring ─────────────────────────────────────────────────────────

  /// Number of questions in a single round.
  final int questionsPerRound;

  /// Point value tiers indexed by wrong attempts before solving.
  /// e.g. [10, 5, 3, 1] → 0 wrong = 10 pts, 1 wrong = 5 pts, 2 wrong = 3 pts, 3+ = 1 pt.
  final List<int> pointTiers;

  /// Score required to clear the level (progress to next level).
  final int pointsToClear;

  /// Score required to master the level (earn recognition).
  final int pointsToMaster;

  const LevelSpecs({
    required this.id,
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
    this.simpleNuggetSeries,
    this.allowedMotions = const [],
    this.questionsPerRound = 20,
    this.pointTiers = const [10, 5, 3, 1],
    this.pointsToClear = 160,   // 80% of 200
    this.pointsToMaster = 180,  // 90% of 200
  });

  factory LevelSpecs.fromJson(Map<String, dynamic> json) {
    NoteNugget nuggetFromJson(Map<String, dynamic> n) => NoteNugget(
          scaleDegree: n['scaleDegree'] as int,
          chromaticAlteration: (n['chromaticAlteration'] as int?) ?? 0,
          octave: (n['octave'] as int?) ?? 0,
        );

    return LevelSpecs(
      id: json['id'] as String,
      levelTitle: json['title'] as String,
      levelType: LevelType.values.byName(json['levelType'] as String),
      availableNoteNuggets: (json['availableNoteNuggets'] as List)
          .map((n) => nuggetFromJson(n as Map<String, dynamic>))
          .toList(),
      howManyAtATime: (json['howManyAtATime'] as int?) ?? 1,
      howManyInARow: (json['howManyInARow'] as int?) ?? 1,
      noTwiceInARow: (json['noTwiceInARow'] as bool?) ?? false,
      answerTokensMakeASound: (json['answerTokensMakeASound'] as bool?) ?? true,
      puzzleGenerationMethod: PuzzleGenerationMethod.values
          .byName(json['puzzleGenerationMethod'] as String),
      questionTokenSymbolMode: QuestionTokenSymbolMode.values
          .byName(json['questionTokenSymbolMode'] as String),
      preferredMode: json['preferredMode'] != null
          ? Mode.values.byName(json['preferredMode'] as String)
          : null,
      widestChromaticRange: (json['widestChromaticRange'] as int?) ?? 0,
      preferredFirstNote: json['preferredFirstNote'] != null
          ? nuggetFromJson(json['preferredFirstNote'] as Map<String, dynamic>)
          : null,
      simpleNuggetSeries: json['simpleNuggetSeries'] != null
          ? (json['simpleNuggetSeries'] as List).cast<int>()
          : null,
      allowedMotions: json['allowedMotions'] != null
          ? (json['allowedMotions'] as List)
              .map((pair) => (pair as List).cast<int>())
              .toList()
          : const [],
      questionsPerRound: (json['questionsPerRound'] as int?) ?? 20,
      pointTiers: json['pointTiers'] != null
          ? (json['pointTiers'] as List).cast<int>()
          : const [10, 5, 3, 1],
      pointsToClear: (json['pointsToClear'] as int?) ?? 160,
      pointsToMaster: (json['pointsToMaster'] as int?) ?? 180,
    );
  }

  /// Loads all levels from assets/levels/levels.json.
  static Future<List<LevelSpecs>> loadAll() async {
    final raw = await rootBundle.loadString('assets/levels/levels.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return (data['levels'] as List)
        .map((e) => LevelSpecs.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
