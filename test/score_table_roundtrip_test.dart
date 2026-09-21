import 'package:flutter_test/flutter_test.dart';
import 'package:ear_training_app/utils/score_table.dart';
import 'package:ear_training_app/utils/solfege_parser.dart';

/// Compare two parses by their rendered note shape (ignoring sourceStart).
String _shape(String text) {
  final r = SolfegeParser.parse(text);
  return r.notes
      .map((n) => n.isLineBreak
          ? 'BR'
          : n.isSpacer
              ? 'SP'
              : '${n.lyric ?? ''}|${n.isLyricOnly ? '' : n.syllable}|'
                  '${n.octave}|${n.groupId ?? '-'}')
      .join('  ');
}

void main() {
  group('ScoreTable <-> legacy text round-trip', () {
    final cases = <String>[
      'Ma/do ry/re had/mi',
      'Twin-/do kle/re',
      'do re mi', // solfège only
      'hello/ do', // lyric-only then solfège
      'do _ re', // spacer
      "do' la,", // octave markers
      'do re [] mi fa', // line break
      '| do re | mi', // group
      'Ma/do ry/re | had/mi a/fa | lit-/so tle/la [] lamb/mi', // combined
    ];

    for (final input in cases) {
      test('semantics preserved: "$input"', () {
        final table = ScoreTable.fromSolfegeText(input);
        final out = table.toSolfegeText();
        // The exact whitespace may differ, but the parsed note shape must match.
        expect(_shape(out), _shape(input),
            reason: 'input="$input"  serialized="$out"');
      });
    }

    test('empty text yields a single editable column', () {
      final table = ScoreTable.fromSolfegeText('');
      expect(table.columns.length, 1);
      expect(table.columns.first.cells.length, 1);
      expect(table.toSolfegeText().trim(), '');
    });

    test('voice normalization pads/trims cells', () {
      final table = ScoreTable.fromSolfegeText('Ma/do ry/re');
      table.voiceCount = 3;
      table.normalizeVoices();
      expect(table.columns.every((c) => c.cells.length == 3), true);
      table.voiceCount = 1;
      table.normalizeVoices();
      expect(table.columns.every((c) => c.cells.length == 1), true);
    });
  });
}
