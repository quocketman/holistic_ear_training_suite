import '../models/round_result.dart';

/// Abstract interface for recording and retrieving player progress.
///
/// Implementations:
///   - [LocalProgressRepository]  — stores to device (Hive/sqflite), standalone app
///   - [ScormProgressRepository]  — reports to LMS via SCORM JS API, web embed
///
/// The game always talks to this interface and never to a concrete implementation
/// directly, so switching storage backends requires no changes to game logic.
abstract class ProgressRepository {
  /// Persist the result of a completed round and update the level's
  /// cumulative [LevelProgress].
  Future<void> recordRoundResult(RoundResult result);

  /// Return the cumulative progress for a single level.
  /// Returns a fresh [LevelProgress] (all defaults) if never played.
  Future<LevelProgress> getProgressForLevel(String levelId);

  /// Return progress records for every level that has been played.
  Future<List<LevelProgress>> getAllProgress();

  /// Whether the given level is available to play.
  /// Typically: level 1 is always unlocked; subsequent levels unlock
  /// when the previous level is cleared.
  Future<bool> isLevelUnlocked(String levelId, {required String? previousLevelId});

  /// Erase all stored progress. Used for "reset" / testing.
  Future<void> clearAllProgress();
}
