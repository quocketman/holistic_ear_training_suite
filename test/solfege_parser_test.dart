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

    test('hyphen separates tokens like whitespace', () {
      final r = SolfegeParser.parse('do-re-mi');
      expect(r.unrecognized, isEmpty);
      expect(r.notes.map((n) => n.syllable).toList(), ['do', 're', 'mi']);
    });

    test('/lyric attaches lyric to syllable verbatim', () {
      final r = SolfegeParser.parse('do/Twin re/kle mi/Lit-tle');
      expect(r.notes.length, 3);
      expect(r.notes[0].lyric, 'Twin');
      expect(r.notes[1].lyric, 'kle');
      // Hyphen is a separator, so "Lit-tle" splits the second token off.
      expect(r.notes[2].lyric, 'Lit');
      expect(r.unrecognized, ['tle']);
    });

    test('lyric works with octave markers', () {
      final r = SolfegeParser.parse("do'/high do,/low");
      expect(r.notes.length, 2);
      expect(r.notes[0].octave, 1);
      expect(r.notes[0].lyric, 'high');
      expect(r.notes[1].octave, -1);
      expect(r.notes[1].lyric, 'low');
    });

    test('empty lyric after slash leaves lyric null', () {
      final r = SolfegeParser.parse('do/ re');
      expect(r.notes.length, 2);
      expect(r.notes[0].lyric, isNull);
      expect(r.notes[1].lyric, isNull);
    });

    test('lyric preserves remaining slashes', () {
      final r = SolfegeParser.parse('do/foo/bar');
      expect(r.notes.length, 1);
      expect(r.notes[0].lyric, 'foo/bar');
    });

    test('standalone pipes group surrounded notes', () {
      final r = SolfegeParser.parse('do | re mi fa | sol');
      expect(r.notes.length, 5);
      expect(r.notes[0].groupId, isNull); // do
      expect(r.notes[1].groupId, isNotNull); // re
      expect(r.notes[2].groupId, r.notes[1].groupId); // mi
      expect(r.notes[3].groupId, r.notes[1].groupId); // fa
      expect(r.notes[4].groupId, isNull); // sol
    });

    test('attached pipes group like standalone', () {
      final r = SolfegeParser.parse('do |re mi fa| sol');
      expect(r.notes.length, 5);
      expect(r.notes[0].groupId, isNull);
      expect(r.notes[1].groupId, isNotNull);
      expect(r.notes[2].groupId, r.notes[1].groupId);
      expect(r.notes[3].groupId, r.notes[1].groupId);
      expect(r.notes[4].groupId, isNull);
    });

    test('multiple groups have distinct ids', () {
      final r = SolfegeParser.parse('|do re| |mi fa|');
      expect(r.notes.length, 4);
      expect(r.notes[0].groupId, isNotNull);
      expect(r.notes[1].groupId, r.notes[0].groupId);
      expect(r.notes[2].groupId, isNotNull);
      expect(r.notes[2].groupId, isNot(r.notes[0].groupId));
      expect(r.notes[3].groupId, r.notes[2].groupId);
    });

    test('groups work with lyrics', () {
      final r = SolfegeParser.parse('|do/twin re/kle|');
      expect(r.notes.length, 2);
      expect(r.notes[0].lyric, 'twin');
      expect(r.notes[1].lyric, 'kle');
      expect(r.notes[0].groupId, isNotNull);
      expect(r.notes[0].groupId, r.notes[1].groupId);
    });
  });
}
