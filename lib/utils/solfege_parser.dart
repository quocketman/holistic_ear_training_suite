/// Parses a string of solfège syllables into a list of pitched notes.
///
/// Syntax:
///   - Syllables separated by whitespace
///   - Trailing `'` (apostrophe) raises octave by 1 each (e.g. `do'`, `do''`)
///   - Trailing `,` lowers octave by 1 each (e.g. `do,`, `do,,`)
///   - Case-insensitive
///
/// Recognised chromatic syllables (offset 0–11):
///   do(0) di/ra(1) re(2) ri/me(3) mi(4) fa(5) fi/se(6)
///   so/sol(7) si/le(8) la(9) li/te(10) ti(11)
class SolfegeNote {
  final String syllable;
  final int chromaticOffset;
  final int octave;

  /// A spacer takes up horizontal space but renders no token.
  final bool isSpacer;

  const SolfegeNote({
    required this.syllable,
    required this.chromaticOffset,
    required this.octave,
    this.isSpacer = false,
  });

  /// Total chromatic position from base do (octave 0, offset 0).
  int get totalChromatic => chromaticOffset + octave * 12;

  @override
  String toString() => '$syllable(off=$chromaticOffset, oct=$octave)';
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

    final tokens = input.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);

    for (final raw in tokens) {
      var token = raw.trim();
      if (token.isEmpty) continue;

      // Underscores = spacers (one per underscore character).
      if (RegExp(r'^_+$').hasMatch(token)) {
        for (var i = 0; i < token.length; i++) {
          notes.add(const SolfegeNote(
            syllable: '_',
            chromaticOffset: 0,
            octave: 0,
            isSpacer: true,
          ));
        }
        continue;
      }

      token = token.toLowerCase();

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
        continue;
      }
      notes.add(SolfegeNote(
        syllable: token,
        chromaticOffset: offset,
        octave: octave,
      ));
    }

    return SolfegeParseResult(notes: notes, unrecognized: unrecognized);
  }
}
