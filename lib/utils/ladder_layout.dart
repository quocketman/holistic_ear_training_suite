import 'dart:ui';
import '../models/note_nugget.dart';
import '../models/enums.dart';

/// A single slot in the alternating ladder layout.
class LadderSlot {
  /// The diatonic note for this slot (with mode-appropriate alteration).
  final NoteNugget nugget;

  /// Chromatic distance (in semitones) from the lowest slot.
  final int semitoneFromBottom;

  /// Horizontal side: -1 left, 0 center, 1 right.
  int side;

  /// Whether this note is in the level's available set.
  final bool isActive;

  LadderSlot({
    required this.nugget,
    required this.semitoneFromBottom,
    required this.side,
    required this.isActive,
  });
}

/// Computes the absolute chromatic position for a NoteNugget in a given mode.
int _absPosition(NoteNugget n, Mode mode) {
  return mode.offsets[n.scaleDegree - 1] + n.chromaticAlteration + n.octave * 12;
}

/// Builds diatonic ladder slots for a set of available notes in a given mode.
///
/// Surveys the available notes to find the full range, then walks all diatonic
/// degrees between lowest and highest (across octaves as needed). Each degree
/// gets one slot with the appropriate alteration for the mode/level.
///
/// Slots alternate left/right by scale degree:
///   degrees 1,3,5,7 → left (-1)
///   degrees 2,4,6   → right (1)
/// with the bottom-most and top-most slots centered (0).
List<LadderSlot> buildLadderSlots({
  required List<NoteNugget> availableNotes,
  required Mode mode,
  int widestChromaticRange = 0,
}) {
  if (availableNotes.isEmpty) return [];

  // Build a lookup: (scaleDegree, octave) → NoteNugget from available notes.
  final available = <(int, int), NoteNugget>{};
  for (final n in availableNotes) {
    available[(n.scaleDegree, n.octave)] = n;
  }

  // Find the absolute chromatic range of available notes.
  final positions = availableNotes.map((n) => _absPosition(n, mode)).toList();
  final lowestPos = positions.reduce((a, b) => a < b ? a : b);
  final highestPos = positions.reduce((a, b) => a > b ? a : b);

  // Determine the chromatic ceiling: either widestChromaticRange from lowest,
  // or the highest available note, whichever is larger.
  final ceiling = widestChromaticRange > 0
      ? lowestPos + widestChromaticRange - 1
      : highestPos;

  // Find which degree/octave corresponds to the lowest available note.
  final lowestNote = availableNotes.firstWhere(
    (n) => _absPosition(n, mode) == lowestPos,
  );

  // Walk diatonic degrees from the lowest note upward until we exceed the ceiling.
  final slots = <LadderSlot>[];
  int currentOctave = lowestNote.octave;
  int currentDegree = lowestNote.scaleDegree;

  while (true) {
    // Determine alteration: use available note's alteration if present,
    // else mode default (alteration 0).
    final availableNote = available[(currentDegree, currentOctave)];
    final alteration = availableNote?.chromaticAlteration ?? 0;
    final nugget = NoteNugget(
      scaleDegree: currentDegree,
      chromaticAlteration: alteration,
      octave: currentOctave,
    );

    final absPos = _absPosition(nugget, mode);

    // Stop if we've exceeded the ceiling.
    if (absPos > ceiling) break;

    // Only include if at or above the lowest position.
    if (absPos >= lowestPos) {
      // Fixed alternation by scale degree.
      final side = (currentDegree.isOdd) ? -1 : 1;

      slots.add(LadderSlot(
        nugget: nugget,
        semitoneFromBottom: absPos - lowestPos,
        side: side,
        isActive: availableNote != null,
      ));
    }

    // Advance to next diatonic degree.
    currentDegree++;
    if (currentDegree > 7) {
      currentDegree = 1;
      currentOctave++;
    }
  }

  // Override: bottom-most and top-most slots are centered.
  if (slots.isNotEmpty) {
    slots.first.side = 0;
    slots.last.side = 0;
  }

  return slots;
}

/// The total height needed for a set of ladder slots at the given token size,
/// where each chromatic half-step occupies exactly [tokenSize] vertical pixels.
double ladderHeight({
  required List<LadderSlot> slots,
  required double tokenSize,
}) {
  if (slots.isEmpty) return tokenSize;
  return tokenSize + slots.last.semitoneFromBottom * tokenSize;
}

/// Computes pixel positions (centers) for ladder slots.
///
/// Each chromatic half-step occupies exactly [tokenSize] vertical pixels,
/// ready for a piano keyboard underlay. Bottom = lowest pitch, top = highest.
/// X alternates left/center/right based on [Size] width.
List<Offset> positionsForSlots({
  required List<LadderSlot> slots,
  required Size size,
  required double tokenSize,
}) {
  if (slots.isEmpty) return [];

  final pixelsPerSemitone = tokenSize;

  return slots.map((slot) {
    // Y: bottom = lowest pitch. Screen coords: bottom = high Y.
    final y = size.height -
        tokenSize / 2 -
        slot.semitoneFromBottom * pixelsPerSemitone;

    // X: left, center, or right.
    final x = switch (slot.side) {
      -1 => tokenSize / 2,
      1 => size.width - tokenSize / 2,
      _ => size.width / 2,
    };

    return Offset(x, y);
  }).toList();
}
