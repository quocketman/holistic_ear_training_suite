import 'package:ear_training_app/utils/solfege_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SolfegeParser', () {
    test('parses bare syllables to chromatic offsets', () {
      final r = SolfegeParser.parse('do re mi fa sol la ti');
      expect(r.unrecognized, isEmpty);
      expect(r.notes.map((n) => n.chromaticOffset).toList(),
          [0, 2, 4, 5, 7, 9, 11]);
      expect(r.notes.every((n) => n.octave == 0), isTrue);
    });

    test("apostrophe raises octave, comma lowers", () {
      final r = SolfegeParser.parse("do do' do'' do, do,,");
      expect(r.notes.map((n) => n.octave).toList(), [0, 1, 2, -1, -2]);
      expect(r.notes.every((n) => n.chromaticOffset == 0), isTrue);
      expect(r.notes.map((n) => n.totalChromatic).toList(),
          [0, 12, 24, -12, -24]);
    });

    test('chromatic alternates map to same offset', () {
      final r = SolfegeParser.parse('di ra ri me fi se si le li te');
      expect(r.unrecognized, isEmpty);
      expect(r.notes.map((n) => n.chromaticOffset).toList(),
          [1, 1, 3, 3, 6, 6, 8, 8, 10, 10]);
    });

    test('case insensitive and preserves original syllable', () {
      final r = SolfegeParser.parse("DO Re mI'");
      expect(r.notes.map((n) => n.syllable).toList(), ['do', 're', 'mi']);
      expect(r.notes[2].octave, 1);
    });

    test('unrecognized tokens collected', () {
      final r = SolfegeParser.parse('do bogus mi');
      expect(r.notes.length, 2);
      expect(r.unrecognized, ['bogus']);
    });

    test('empty input yields empty result', () {
      final r = SolfegeParser.parse('   ');
      expect(r.notes, isEmpty);
      expect(r.unrecognized, isEmpty);
    });

    test('sol and so both map to offset 7', () {
      final r = SolfegeParser.parse('so sol');
      expect(r.notes.map((n) => n.chromaticOffset).toList(), [7, 7]);
    });
  });
}
