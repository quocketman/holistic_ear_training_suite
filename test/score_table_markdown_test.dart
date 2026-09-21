import 'package:flutter_test/flutter_test.dart';
import 'package:ear_training_app/utils/score_table.dart';

String _dump(ScoreTable t) {
  final b = StringBuffer('voices=${t.voiceCount}\n');
  for (final col in t.columns) {
    b.write('[');
    b.write(col.cells.map((c) => '${c.text}/${c.solfege}').join(' , '));
    b.write(col.isSpacer ? ' SP' : '');
    b.write(col.groupStart ? ' (' : '');
    b.write(col.groupEnd ? ' )' : '');
    b.write(col.breakAfter ? ' BR' : '');
    b.write('] ');
  }
  return b.toString();
}

void main() {
  group('Markdown round-trip', () {
    test('single voice from legacy text', () {
      final t = ScoreTable.fromSolfegeText(
          'Ma/do ry/re | had/mi a/fa | lit-/so tle/la [] lamb/mi');
      final md = t.toMarkdown();
      final back = ScoreTable.fromMarkdown(md);
      expect(_dump(back), _dump(t), reason: 'markdown:\n$md');
    });

    test('two voices preserved', () {
      final t = ScoreTable(
        voiceCount: 2,
        columns: [
          ScoreColumn(cells: [
            ScoreCell(text: 'Ma', solfege: 'do'),
            ScoreCell(text: 'ah', solfege: 'mi'),
          ]),
          ScoreColumn(cells: [
            ScoreCell(text: 'ry', solfege: 're'),
            ScoreCell(text: 'ah', solfege: 'fa'),
          ], breakAfter: true),
          ScoreColumn(cells: [
            ScoreCell(text: 'had', solfege: "mi'"),
            ScoreCell(text: 'oo', solfege: 'so'),
          ]),
        ],
      );
      final md = t.toMarkdown();
      final back = ScoreTable.fromMarkdown(md);
      expect(back.voiceCount, 2);
      expect(_dump(back), _dump(t), reason: 'markdown:\n$md');
    });

    test('spacer + group survive markdown', () {
      final t = ScoreTable.fromSolfegeText('do _ | re mi |');
      final back = ScoreTable.fromMarkdown(t.toMarkdown());
      expect(_dump(back), _dump(t));
    });
  });

  group('toParseResult', () {
    test('single voice notes carry column/voice', () {
      final t = ScoreTable.fromSolfegeText('Ma/do ry/re had/mi');
      final r = t.toParseResult();
      final pitched = r.notes.where((n) => !n.isLineBreak && !n.isSpacer);
      expect(pitched.length, 3);
      expect(pitched.every((n) => n.voice == 0), true);
      expect(pitched.map((n) => n.column).toList(), [0, 1, 2]);
      expect(pitched.map((n) => n.syllable).toList(), ['do', 're', 'mi']);
    });

    test('two voices share a column and stack', () {
      final t = ScoreTable(
        voiceCount: 2,
        columns: [
          ScoreColumn(cells: [
            ScoreCell(text: 'Ma', solfege: 'do'),
            ScoreCell(text: 'ah', solfege: 'mi'),
          ]),
        ],
      );
      final notes = t.toParseResult().notes;
      expect(notes.length, 2);
      expect(notes[0].voice, 0);
      expect(notes[1].voice, 1);
      expect(notes.every((n) => n.column == 0), true);
      expect(notes[1].syllable, 'mi');
    });
  });
}
