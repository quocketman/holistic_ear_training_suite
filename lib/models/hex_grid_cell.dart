import 'level_specs.dart';
import 'round_result.dart';

/// A single cell in the hex grid map, aggregating the warm-up/practice/challenge
/// triplet for one note-combination × notes-in-a-row intersection.
class HexGridCell {
  final int row;
  final int column;
  final String displayLabel; // e.g. "do-re"
  final int levelNumber;     // 1-based, by note combination

  final LevelSpecs? warmUpLevel;
  final LevelSpecs? practiceLevel;
  final LevelSpecs? challengeLevel;

  final bool warmUpCleared;
  final bool warmUpMastered;
  final bool practiceCleared;
  final bool practiceMastered;
  final bool challengeCleared;
  final bool challengeMastered;

  bool isUnlocked;

  HexGridCell({
    required this.row,
    required this.column,
    required this.displayLabel,
    required this.levelNumber,
    this.warmUpLevel,
    this.practiceLevel,
    this.challengeLevel,
    this.warmUpCleared = false,
    this.warmUpMastered = false,
    this.practiceCleared = false,
    this.practiceMastered = false,
    this.challengeCleared = false,
    this.challengeMastered = false,
    this.isUnlocked = false,
  });

  /// Whether this cell has any real levels (not a future placeholder).
  bool get hasLevels =>
      warmUpLevel != null || practiceLevel != null || challengeLevel != null;

  /// Whether the challenge phase is cleared (full cell completion).
  bool get isCleared => challengeCleared;

  /// The first level spec to use as a representative (for connection visualizer, etc).
  LevelSpecs? get representativeLevel =>
      warmUpLevel ?? practiceLevel ?? challengeLevel;

  /// Ordered list of the cell's non-null levels.
  List<LevelSpecs> get cellLevels => [
        if (warmUpLevel != null) warmUpLevel!,
        if (practiceLevel != null) practiceLevel!,
        if (challengeLevel != null) challengeLevel!,
      ];

  /// The first level whose phase is not yet cleared, for tap navigation.
  LevelSpecs? get firstUncompletedLevel {
    if (warmUpLevel != null && !warmUpCleared) return warmUpLevel;
    if (practiceLevel != null && !practiceCleared) return practiceLevel;
    if (challengeLevel != null && !challengeCleared) return challengeLevel;
    // All cleared — return practice for replay.
    return practiceLevel ?? warmUpLevel ?? challengeLevel;
  }

  /// Index of [firstUncompletedLevel] within [cellLevels].
  int get firstUncompletedIndex {
    final target = firstUncompletedLevel;
    final idx = cellLevels.indexOf(target!);
    return idx >= 0 ? idx : 0;
  }
}
