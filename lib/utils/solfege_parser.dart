/// Parses a string of lyrics and solfège syllables into a list of pitched
/// notes and lyric-only entries.
///
/// Syntax (lyric-first model — 2026-06-09):
///   - Tokens are separated by whitespace.
///   - Hyphens (`-`) inside a token are preserved as part of the lyric text.
///   - A token containing `/` splits into `lyric/solfège`:
///       `Mary/do`     → lyric "Mary" + solfège "do"
///       `Twink-/so`   → lyric "Twink-" + solfège "so"
///       `do/`         → lyric "do" (trailing slash forces lyric)
///       `/do`         → solfège only (leading slash is decorative)
///   - A token without `/` is classified by whole-string match:
///       known syllable → solfège (hex + label)
///       otherwise      → lyric only (no hex)
///   - Solfège octave markers: trailing `'` raises by 1 each, `,` lowers by 1
///     each. Applies to the solfège portion only (`Mary/do'`, `do''`).
///   - Underscore (`_`) inserts a blank spacer. Repeated for wider gaps.
///   - Pipe (`|`) groups notes for visual clustering. May be standalone or
///     attached to a token.
///
/// Recognised chromatic syllables (offset 0–11):
///   do(0) di/ra(1) re(2) ri/me(3) mi(4) fa(5) fi/se(6)
///   so/sol(7) si/le(8) la(9) li/te(10) ti(11)
class SolfegeNote {
  final String syllable;
  final int chromaticOffset;
  final int octave;
  final String? lyric;

  /// A spacer takes up horizontal space but renders no token.
  final bool isSpacer;

  /// A lyric-only note has no pitch — renders just the lyric text, positioned
  /// at the vertical center of the canvas (or interpolated between flanking
  /// pitched notes).
  final bool isLyricOnly;

  /// Optional group identifier — notes with the same id render with a faint
  /// rounded background underneath, visually clustering them.
  final int? groupId;

  const SolfegeNote({
    required this.syllable,
    required this.chromaticOffset,
    required this.octave,
    this.lyric,
    this.isSpacer = false,
    this.isLyricOnly = false,
    this.groupId,
  });

  /// Total chromatic position from base do (octave 0, offset 0).
  int get totalChromatic => chromaticOffset + octave * 12;

  @override
  String toString() =>
      '${isLyricOnly ? "[lyric]" : syllable}'
      '(off=$chromaticOffset, oct=$octave'
      '${lyric == null ? '' : ', lyric=$lyric'}'
      '${isLyricOnly ? ', lyricOnly' : ''}'
      '${groupId == null ? '' : ', group=$groupId'})';
}

class SolfegeParseResult {
  final List<SolfegeNote> notes;
  final List<String> unrecognized;

  const SolfegeParseResult({required this.notes, required this.unrecognized});
}

class SolfegeParser {
  static const Map<String, int> _syllableMap = {
    'do': 0,
    'di': 1,
    'ra': 1,
    're': 2,
    'ri': 3,
    'me': 3,
    'mi': 4,
    'fa': 5,
    'fi': 6,
    'se': 6,
    'so': 7,
    'sol': 7,
    'si': 8,
    'le': 8,
    'la': 9,
    'li': 10,
    'te': 10,
    'ti': 11,
  };

  static List<String> get knownSyllables => _syllableMap.keys.toList();

  /// Returns true if [token] (after octave-marker stripping and lowercasing)
  /// is one of the recognised chromatic syllables. Used by the input field's
  /// syntax-highlighting logic to italicise solfège as the user types.
  static bool isKnownSyllable(String token) {
    var t = token.toLowerCase().trim();
    while (t.endsWith("'") || t.endsWith(',')) {
      t = t.substring(0, t.length - 1);
    }
    return _syllableMap.containsKey(t);
  }

  static SolfegeParseResult parse(String input) {
    final notes = <SolfegeNote>[];
    final unrecognized = <String>[];

    // Whitespace-only split — hyphens stay inside tokens as lyric chars.
    final tokens = input.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);

    int? currentGroup;
    int nextGroupId = 0;

    for (final raw in tokens) {
      // Standalone pipe(s): each `|` toggles group state.
      if (RegExp(r'^\|+$').hasMatch(raw)) {
        for (var i = 0; i < raw.length; i++) {
          if (currentGroup == null) {
            currentGroup = nextGroupId++;
          } else {
            currentGroup = null;
          }
        }
        continue;
      }

      // Strip leading/trailing pipes from the token.
      var working = raw;
      var openBefore = false;
      var closeAfter = false;
      while (working.startsWith('|')) {
        openBefore = !openBefore;
        working = working.substring(1);
      }
      while (working.endsWith('|')) {
        closeAfter = !closeAfter;
        working = working.substring(0, working.length - 1);
      }

      if (openBefore) {
        currentGroup = nextGroupId++;
      }

      // Underscores = spacers (one per underscore character).
      if (RegExp(r'^_+$').hasMatch(working)) {
        for (var i = 0; i < working.length; i++) {
          notes.add(SolfegeNote(
            syllable: '_',
            chromaticOffset: 0,
            octave: 0,
            isSpacer: true,
            groupId: currentGroup,
          ));
        }
        if (closeAfter) currentGroup = null;
        continue;
      }

      // Decide what the token represents.
      String? lyric;
      String? solfPart;

      final slash = working.lastIndexOf('/');
      if (slash >= 0) {
        // Split at the last slash so lyrics can legitimately contain `/`
        // (e.g. `and/or/do` → lyric "and/or" + solfège "do").
        final before = working.substring(0, slash);
        final after = working.substring(slash + 1);
        if (before.isNotEmpty) lyric = before;
        if (after.isNotEmpty) solfPart = after;
      } else {
        // No slash — classify by whole-string match against the syllable map.
        if (isKnownSyllable(working)) {
          solfPart = working;
        } else {
          lyric = working;
        }
      }

      // Pure lyric-only — no pitch, just text.
      if (solfPart == null) {
        if (lyric == null) {
          // Empty token (e.g. just a slash). Skip.
          if (closeAfter) currentGroup = null;
          continue;
        }
        notes.add(SolfegeNote(
          syllable: '',
          chromaticOffset: 0,
          octave: 0,
          lyric: lyric,
          isLyricOnly: true,
          groupId: currentGroup,
        ));
        if (closeAfter) currentGroup = null;
        continue;
      }

      // Parse solfège portion (octave markers + map lookup).
      var token = solfPart.toLowerCase().trim();
      var octave = 0;
      while (token.endsWith("'")) {
        octave += 1;
        token = token.substring(0, token.length - 1);
      }
      while (token.endsWith(',')) {
        octave -= 1;
        token = token.substring(0, token.length - 1);
      }

      final offset = _syllableMap[token];
      if (offset == null) {
        // Solfège part unrecognised — record but don't render.
        unrecognized.add(raw);
        if (closeAfter) currentGroup = null;
        continue;
      }
      notes.add(SolfegeNote(
        syllable: token,
        chromaticOffset: offset,
        octave: octave,
        lyric: lyric,
        groupId: currentGroup,
      ));

      if (closeAfter) currentGroup = null;
    }

    return SolfegeParseResult(notes: notes, unrecognized: unrecognized);
  }
}
