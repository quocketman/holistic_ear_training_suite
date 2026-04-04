/// The outcome of a single completed round of ToneHole.
/// Carries everything needed for local storage and SCORM reporting.
class RoundResult {
  /// ID of the level that was played (matches LevelSpecs.id).
  final String levelId;

  /// When the round ended.
  final DateTime completedAt;

  /// Raw score accumulated during the round.
  final int totalPoints;

  /// Maximum possible score for this round (questionsPerRound × pointTiers.first).
  final int maxPossiblePoints;

  /// Number of questions answered (always == questionsPerRound on a full round).
  final int questionsAnswered;

  /// Questions answered correctly on the first tap.
  final int firstTryCorrect;

  /// Total wrong taps across the round.
  final int totalWrongTaps;

  /// Whether the player met the clear threshold.
  final bool cleared;

  /// Whether the player met the master threshold.
  final bool mastered;

  /// How long the round took, in seconds. Used for SCORM session_time.
  final int durationSeconds;

  const RoundResult({
    required this.levelId,
    required this.completedAt,
    required this.totalPoints,
    required this.maxPossiblePoints,
    required this.questionsAnswered,
    required this.firstTryCorrect,
    required this.totalWrongTaps,
    required this.cleared,
    required this.mastered,
    required this.durationSeconds,
  });

  /// Score as a 0–100 percentage. Used for SCORM cmi.core.score.raw.
  double get scorePercent => maxPossiblePoints > 0
      ? (totalPoints / maxPossiblePoints) * 100.0
      : 0.0;

  Map<String, dynamic> toJson() => {
        'levelId': levelId,
        'completedAt': completedAt.toIso8601String(),
        'totalPoints': totalPoints,
        'maxPossiblePoints': maxPossiblePoints,
        'questionsAnswered': questionsAnswered,
        'firstTryCorrect': firstTryCorrect,
        'totalWrongTaps': totalWrongTaps,
        'cleared': cleared,
        'mastered': mastered,
        'durationSeconds': durationSeconds,
      };

  factory RoundResult.fromJson(Map<String, dynamic> json) => RoundResult(
        levelId: json['levelId'] as String,
        completedAt: DateTime.parse(json['completedAt'] as String),
        totalPoints: json['totalPoints'] as int,
        maxPossiblePoints: json['maxPossiblePoints'] as int,
        questionsAnswered: json['questionsAnswered'] as int,
        firstTryCorrect: json['firstTryCorrect'] as int,
        totalWrongTaps: json['totalWrongTaps'] as int,
        cleared: json['cleared'] as bool,
        mastered: json['mastered'] as bool,
        durationSeconds: json['durationSeconds'] as int,
      );
}

/// Accumulated progress for a single level across all rounds ever played.
class LevelProgress {
  final String levelId;

  /// Whether the player has ever cleared this level.
  final bool everCleared;

  /// Whether the player has ever mastered this level.
  final bool everMastered;

  /// Highest score ever achieved on this level.
  final int bestScore;

  /// Total number of rounds played on this level.
  final int roundsPlayed;

  /// When this level was last played.
  final DateTime? lastPlayedAt;

  const LevelProgress({
    required this.levelId,
    this.everCleared = false,
    this.everMastered = false,
    this.bestScore = 0,
    this.roundsPlayed = 0,
    this.lastPlayedAt,
  });

  /// Returns an updated copy after applying a new round result.
  LevelProgress applying(RoundResult result) => LevelProgress(
        levelId: levelId,
        everCleared: everCleared || result.cleared,
        everMastered: everMastered || result.mastered,
        bestScore: result.totalPoints > bestScore ? result.totalPoints : bestScore,
        roundsPlayed: roundsPlayed + 1,
        lastPlayedAt: result.completedAt,
      );

  Map<String, dynamic> toJson() => {
        'levelId': levelId,
        'everCleared': everCleared,
        'everMastered': everMastered,
        'bestScore': bestScore,
        'roundsPlayed': roundsPlayed,
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
      };

  factory LevelProgress.fromJson(Map<String, dynamic> json) => LevelProgress(
        levelId: json['levelId'] as String,
        everCleared: json['everCleared'] as bool? ?? false,
        everMastered: json['everMastered'] as bool? ?? false,
        bestScore: json['bestScore'] as int? ?? 0,
        roundsPlayed: json['roundsPlayed'] as int? ?? 0,
        lastPlayedAt: json['lastPlayedAt'] != null
            ? DateTime.parse(json['lastPlayedAt'] as String)
            : null,
      );
}
