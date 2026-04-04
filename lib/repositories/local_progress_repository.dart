import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/round_result.dart';
import 'progress_repository.dart';

/// Stores player progress locally using Hive.
/// Works on mobile, desktop, and web — required for SCORM web embedding.
class LocalProgressRepository implements ProgressRepository {
  static const _progressBoxName = 'level_progress';
  static const _resultsBoxName = 'round_results';

  late Box _progressBox;
  late Box _resultsBox;

  /// Must be called once at app startup before any repository methods are used.
  /// Call after [Hive.initFlutter()].
  Future<void> init() async {
    _progressBox = await Hive.openBox(_progressBoxName);
    _resultsBox = await Hive.openBox(_resultsBoxName);
  }

  @override
  Future<void> recordRoundResult(RoundResult result) async {
    // Append the raw round result (keyed by auto-increment).
    await _resultsBox.add(jsonEncode(result.toJson()));

    // Update the cumulative level progress.
    final current = await getProgressForLevel(result.levelId);
    final updated = current.applying(result);
    await _progressBox.put(result.levelId, jsonEncode(updated.toJson()));
  }

  @override
  Future<LevelProgress> getProgressForLevel(String levelId) async {
    final raw = _progressBox.get(levelId);
    if (raw == null) return LevelProgress(levelId: levelId);
    return LevelProgress.fromJson(
      jsonDecode(raw as String) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<LevelProgress>> getAllProgress() async {
    return _progressBox.values
        .map((v) => LevelProgress.fromJson(
              jsonDecode(v as String) as Map<String, dynamic>,
            ))
        .toList();
  }

  @override
  Future<bool> isLevelUnlocked(
    String levelId, {
    required String? previousLevelId,
  }) async {
    // The first level is always unlocked.
    if (previousLevelId == null) return true;
    final prev = await getProgressForLevel(previousLevelId);
    return prev.everCleared;
  }

  @override
  Future<void> clearAllProgress() async {
    await _progressBox.clear();
    await _resultsBox.clear();
  }

  /// Returns all stored round results, newest first.
  Future<List<RoundResult>> getAllRoundResults() async {
    return _resultsBox.values
        .map((v) => RoundResult.fromJson(
              jsonDecode(v as String) as Map<String, dynamic>,
            ))
        .toList()
        .reversed
        .toList();
  }
}
