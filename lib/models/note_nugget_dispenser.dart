import 'dart:math';
import 'note_nugget.dart';
import 'level_specs.dart';

/// Manages a list of NoteNuggets with a cursor for sequential or random access.
/// Mirrors LUNoteNuggetDispenser.
class NoteNuggetDispenser {
  final List<NoteNugget> _nuggets;
  int _index = 0;
  final _random = Random();

  /// If false (default), nuggets are kept sorted by scale degree and alteration.
  /// If true, the order in which nuggets were added is preserved.
  final bool retainSubmittedOrder;

  NoteNuggetDispenser({
    required LevelSpecs levelSpecs,
    this.retainSubmittedOrder = false,
  }) : _nuggets = List<NoteNugget>.from(levelSpecs.availableNoteNuggets) {
    if (!retainSubmittedOrder) _sort();
  }

  // ── Basic info ──────────────────────────────────────────────────────────────

  int get count => _nuggets.length;

  int get currentIndex => _index;

  bool get isEmpty => _nuggets.isEmpty;

  // ── Index navigation ────────────────────────────────────────────────────────

  /// Advances the index by [amount], wrapping around.
  void incrementIndexBy(int amount) {
    if (_nuggets.isEmpty) return;
    _index = (_index + amount) % _nuggets.length;
  }

  /// Moves the index back by [amount], wrapping around.
  void decrementIndexBy(int amount) {
    if (_nuggets.isEmpty) return;
    _index = (_index - amount) % _nuggets.length;
    if (_index < 0) _index += _nuggets.length;
  }

  void resetIndex() => _index = 0;

  // ── Nugget access ───────────────────────────────────────────────────────────

  /// Returns the nugget at the current index without moving it.
  NoteNugget? get currentNoteNugget {
    if (_nuggets.isEmpty) return null;
    return _nuggets[_index];
  }

  /// Advances the index by 1 and returns the nugget at the new position.
  NoteNugget? get nextNoteNugget {
    if (_nuggets.isEmpty) return null;
    incrementIndexBy(1);
    return _nuggets[_index];
  }

  /// Moves the index back by 1 and returns the nugget at the new position.
  NoteNugget? get previousNoteNugget {
    if (_nuggets.isEmpty) return null;
    decrementIndexBy(1);
    return _nuggets[_index];
  }

  /// Returns a random nugget without moving the index.
  NoteNugget? get randomNoteNugget {
    if (_nuggets.isEmpty) return null;
    return _nuggets[_random.nextInt(_nuggets.length)];
  }

  /// Weighted random pick: biased toward [nextNoteNugget],
  /// with a smaller chance of [currentNoteNugget] or [previousNoteNugget].
  /// Mirrors LUNoteNuggetDispenser's nextPreviousOrCurrentNoteNugget.
  NoteNugget? get nextPreviousOrCurrentNoteNugget {
    if (_nuggets.isEmpty) return null;
    final int upperBound = _nuggets.length == 2 ? 2 : 8;
    final int middle = _nuggets.length == 2 ? 1 : 3;
    final int roll = _random.nextInt(upperBound);
    if (roll < middle) return previousNoteNugget;
    if (roll > middle) return nextNoteNugget;
    return currentNoteNugget;
  }

  NoteNugget? get firstNoteNugget => _nuggets.isEmpty ? null : _nuggets.first;

  NoteNugget? get lowestNoteNugget {
    if (_nuggets.isEmpty) return null;
    return _nuggets.reduce((a, b) => _isLower(a, b) ? a : b);
  }

  // ── Mutation ────────────────────────────────────────────────────────────────

  void addNoteNugget(NoteNugget nugget) {
    _nuggets.add(nugget);
    if (!retainSubmittedOrder) _sort();
  }

  void replaceAllNuggets(List<NoteNugget> nuggets) {
    _nuggets
      ..clear()
      ..addAll(nuggets);
    _index = 0;
    if (!retainSubmittedOrder) _sort();
  }

  void removeNugget(NoteNugget nugget) {
    _nuggets.removeWhere((n) => n == nugget);
    if (_index >= _nuggets.length && _nuggets.isNotEmpty) {
      _index = _nuggets.length - 1;
    }
  }

  void removeAllNuggets() {
    _nuggets.clear();
    _index = 0;
  }

  void shuffle() {
    _nuggets.shuffle(_random);
    _index = 0;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _sort() {
    _nuggets.sort((a, b) {
      final degreeCompare = a.scaleDegree.compareTo(b.scaleDegree);
      if (degreeCompare != 0) return degreeCompare;
      return a.chromaticAlteration.compareTo(b.chromaticAlteration);
    });
  }

  /// Returns true if [a] is lower in pitch than [b]
  /// (lower octave first, then lower scale degree, then lower alteration).
  bool _isLower(NoteNugget a, NoteNugget b) {
    if (a.octave != b.octave) return a.octave < b.octave;
    if (a.scaleDegree != b.scaleDegree) return a.scaleDegree < b.scaleDegree;
    return a.chromaticAlteration < b.chromaticAlteration;
  }
}
