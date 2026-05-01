/// Parses a string of solfège syllables (and optional lyric pairings) into
/// a list of pitched notes.
///
/// Syntax:
///   - Tokens separated by whitespace OR hyphen (`-`)
///   - Trailing `'` (apostrophe) raises octave by 1 each (e.g. `do'`, `do''`)
///   - Trailing `,` lowers octave by 1 each (e.g. `do,`, `do,,`)
///   - Optional `/lyric` suffix attaches a lyric to the syllable
///     (e.g. `do/twin re/kle`). The lyric is preserved verbatim, including
///     case. Anything after the first `/` is the lyric.
///   - Solfège portion is case-insensitive
///   - Underscore (`_`) inserts a blank spacer the width of a hex.
///     Multiple underscores create wider gaps (e.g. `___`).
///   - Pipe (`|`) groups notes for visual clustering. May be a standalone
///     token or attached to a syllable. Examples:
///       `do | re mi fa | sol`     → re, mi, fa grouped
///       `do |re mi fa| sol`       → same as above
///       `|do re| |mi fa|`         → two separate groups
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

  /// Optional group identifier — notes with the same id render with a faint
  /// rounded background underneath, visually clustering them.
  final int? groupId;

  const SolfegeNote({
    required this.syllable,
    required this.chromaticOffset,
    required this.octave,
    this.lyric,
    this.isSpacer = false,
    this.groupId,
  });

  /// Total chromatic position from base do (octave 0, offset 0).
  int get totalChromatic => chromaticOffset + octave * 12;

  @override
  String toString() =>
      '$syllable(off=$chromaticOffset, oct=$octave'
      '${lyric == null ? '' : ', lyric=$lyric'}'
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

  static SolfegeParseResult parse(String input) {
    final notes = <SolfegeNote>[];
    final unrecognized = <String>[];

    final tokens = input.split(RegExp(r'[\s\-]+')).where((t) => t.isNotEmpty);

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

      // Strip leading/trailing pipes from the token. A leading pipe opens a
      // new group; a trailing pipe closes the current group after this note.
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
        // Close any existing group, then open a fresh one.
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

      // Split off optional lyric (everything after the first '/').
      String solfPart = working;
      String? lyric;
      final slash = working.indexOf('/');
      if (slash >= 0) {
        solfPart = working.substring(0, slash);
        final rest = working.substring(slash + 1);
        if (rest.isNotEmpty) lyric = rest;
      }

      var token = solfPart.toLowerCase().trim();
      if (token.isEmpty) {
        unrecognized.add(raw);
        if (closeAfter) currentGroup = null;
        continue;
      }

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
