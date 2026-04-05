import '../models/level_specs.dart';
import '../models/round_result.dart';
import '../models/hex_grid_cell.dart';

/// Number of notes-in-a-row columns to show (including future placeholders).
const int hexGridColumns = 4;

/// Extract a short display label from a set name like "SET 1 (do-re)" → "do-re".
String _displayLabel(String setName) {
  final match = RegExp(r'\(([^)]+)\)').firstMatch(setName);
  if (match != null) return match.group(1)!;
  // Fallback: strip "SET N " prefix if present.
  return setName.replaceFirst(RegExp(r'^SET \d+ '), '').trim();
}

/// Builds a 2D grid of [HexGridCell]s from a flat list of levels and progress.
///
/// Rows = unique note combination sets (preserving order from JSON).
/// Columns = notes-in-a-row tiers (1, 2, 3, 4).
List<List<HexGridCell>> buildHexGrid(
  List<LevelSpecs> levels,
  List<LevelProgress> progress,
) {
  // Progress lookup by level ID.
  final progressMap = {for (final p in progress) p.levelId: p};

  // Discover unique sets in order, assigning row indices.
  final setOrder = <String>[];
  for (final level in levels) {
    if (!setOrder.contains(level.setName)) {
      setOrder.add(level.setName);
    }
  }

  // Group levels by (setName, howManyInARow).
  final buckets = <(String, int), List<LevelSpecs>>{};
  for (final level in levels) {
    final key = (level.setName, level.howManyInARow);
    (buckets[key] ??= []).add(level);
  }

  // Build the grid.
  final grid = <List<HexGridCell>>[];

  for (int row = 0; row < setOrder.length; row++) {
    final setName = setOrder[row];
    final label = _displayLabel(setName);
    final rowCells = <HexGridCell>[];

    for (int col = 0; col < hexGridColumns; col++) {
      final inARow = col + 1;
      final bucket = buckets[(setName, inARow)];

      LevelSpecs? warmUp, practice, challenge;
      if (bucket != null) {
        for (final l in bucket) {
          switch (l.levelType) {
            case LevelType.warmUp:
              warmUp = l;
            case LevelType.practice:
              practice = l;
            case LevelType.challenge:
              challenge = l;
            default:
              break;
          }
        }
      }

      bool cleared(LevelSpecs? l) =>
          l != null && (progressMap[l.id]?.everCleared ?? false);
      bool mastered(LevelSpecs? l) =>
          l != null && (progressMap[l.id]?.everMastered ?? false);

      rowCells.add(HexGridCell(
        row: row,
        column: col,
        displayLabel: label,
        levelNumber: row + 1,
        warmUpLevel: warmUp,
        practiceLevel: practice,
        challengeLevel: challenge,
        warmUpCleared: cleared(warmUp),
        warmUpMastered: mastered(warmUp),
        practiceCleared: cleared(practice),
        practiceMastered: mastered(practice),
        challengeCleared: cleared(challenge),
        challengeMastered: mastered(challenge),
      ));
    }

    grid.add(rowCells);
  }

  // Unlock logic: cell(0,0) always unlocked.
  // cell(r,c) unlocked if cell(r, c-1).isCleared OR cell(r-1, c).isCleared.
  for (int row = 0; row < grid.length; row++) {
    for (int col = 0; col < hexGridColumns; col++) {
      final cell = grid[row][col];
      if (row == 0 && col == 0) {
        cell.isUnlocked = true;
      } else {
        final leftCleared = col > 0 && grid[row][col - 1].isCleared;
        final aboveCleared = row > 0 && grid[row - 1][col].isCleared;
        cell.isUnlocked = leftCleared || aboveCleared;
      }
      // Placeholder cells (no levels) stay locked regardless.
      if (!cell.hasLevels) cell.isUnlocked = false;
    }
  }

  return grid;
}
