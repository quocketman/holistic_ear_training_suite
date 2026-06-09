import 'package:ear_training_app/utils/solfege_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SolfegeParser — lyric-first syntax (2026-06-09)', () {
    // ── Bare solfège syllables ──────────────────────────────────────────

    test('bare known syllables parse as solfège (no lyric)', () {
      final r = SolfegeParser.parse('do re mi fa sol la ti');
      expect(r.unrecognized, isEmpty);
      expect(r.notes.map((n) => n.chromaticOffset).toList(),
          [0, 2, 4, 5, 7, 9, 11]);
      expect(r.notes.every((n) => n.octave == 0), isTrue);
      expect(r.notes.every((n) => n.isLyricOnly == false), isTrue);
      expect(r.notes.every((n) => n.lyric == null), isTrue);
    });

    test('chromatic alternates map to same offset', () {
      final r = SolfegeParser.parse('di ra ri me fi se si le li te');
      expect(r.unrecognized, isEmpty);
      expect(r.notes.map((n) => n.chromaticOffset).toList(),
          [1, 1, 3, 3, 6, 6, 8, 8, 10, 10]);
    });

    test('case insensitive, syllable stored lowercase', () {
      final r = SolfegeParser.parse("DO Re mI'");
      expect(r.notes.map((n) => n.syllable).toList(), ['do', 're', 'mi']);
      expect(r.notes[2].octave, 1);
    });

    test('sol and so both map to offset 7', () {
      final r = SolfegeParser.parse('so sol');
      expect(r.notes.map((n) => n.chromaticOffset).toList(), [7, 7]);
    });

    test("apostrophe raises octave, comma lowers", () {
      final r = SolfegeParser.parse("do do' do'' do, do,,");
      expect(r.notes.map((n) => n.octave).toList(), [0, 1, 2, -1, -2]);
    });

    // ── New: lyric-first / solfège ───────────────────────────────────────

    test('lyric/solfège: lyric is before, solfège after', () {
      final r = SolfegeParser.parse('Mary/do had/re a/mi');
      expect(r.notes.length, 3);
      expect(r.notes[0].lyric, 'Mary');
      expect(r.notes[0].syllable, 'do');
      expect(r.notes[1].lyric, 'had');
      expect(r.notes[1].syllable, 're');
      expect(r.notes[2].lyric, 'a');
      expect(r.notes[2].syllable, 'mi');
    });

    test('lyrics preserve trailing hyphens for syllable continuation', () {
      final r = SolfegeParser.parse('Twink-/do le/do twink-/so le/so');
      expect(r.notes.map((n) => n.lyric).toList(),
          ['Twink-', 'le', 'twink-', 'le']);
      expect(r.notes.map((n) => n.syllable).toList(),
          ['do', 'do', 'so', 'so']);
    });

    test('lyric works with octave markers on the solfège portion', () {
      final r = SolfegeParser.parse("high/do' low/do,");
      expect(r.notes.length, 2);
      expect(r.notes[0].octave, 1);
      expect(r.notes[0].lyric, 'high');
      expect(r.notes[1].octave, -1);
      expect(r.notes[1].lyric, 'low');
    });

    test('lyric may contain a slash (split is at the LAST slash)', () {
      final r = SolfegeParser.parse('and/or/do');
      expect(r.notes.length, 1);
      expect(r.notes[0].lyric, 'and/or');
      expect(r.notes[0].syllable, 'do');
    });

    // ── Trailing slash → force lyric interpretation ──────────────────────

    test('trailing slash forces a known syllable to be a lyric', () {
      final r = SolfegeParser.parse('do/ re');
      expect(r.notes.length, 2);
      expect(r.notes[0].isLyricOnly, isTrue);
      expect(r.notes[0].lyric, 'do');
      expect(r.notes[1].isLyricOnly, isFalse);
      expect(r.notes[1].syllable, 're');
    });

    test('leading slash gives solfège-only (lyric is null)', () {
      final r = SolfegeParser.parse('/do');
      expect(r.notes.length, 1);
      expect(r.notes[0].lyric, isNull);
      expect(r.notes[0].syllable, 'do');
      expect(r.notes[0].isLyricOnly, isFalse);
    });

    // ── Lyric-only (no solfège) ─────────────────────────────────────────

    test('non-solfège word becomes a lyric-only note', () {
      final r = SolfegeParser.parse('Mary had a little lamb');
      expect(r.notes.length, 5);
      expect(r.notes.every((n) => n.isLyricOnly), isTrue);
      expect(r.notes.map((n) => n.lyric).toList(),
          ['Mary', 'had', 'a', 'little', 'lamb']);
      expect(r.unrecognized, isEmpty);
    });

    test('mixed lyric-only and solfège in one sequence', () {
      final r = SolfegeParser.parse('Mary/do had/re a little/mi lamb');
      expect(r.notes.length, 5);
      expect(r.notes[0].syllable, 'do');
      expect(r.notes[0].lyric, 'Mary');
      expect(r.notes[1].syllable, 're');
      expect(r.notes[1].lyric, 'had');
      expect(r.notes[2].isLyricOnly, isTrue);
      expect(r.notes[2].lyric, 'a');
      expect(r.notes[3].syllable, 'mi');
      expect(r.notes[3].lyric, 'little');
      expect(r.notes[4].isLyricOnly, isTrue);
      expect(r.notes[4].lyric, 'lamb');
    });

    // ── Spacers and groups (carried over) ────────────────────────────────

    test('underscores create spacer notes', () {
      final r = SolfegeParser.parse('do _ re __ mi');
      expect(r.notes.length, 6);
      expect(r.notes[0].isSpacer, isFalse);
      expect(r.notes[1].isSpacer, isTrue);
      expect(r.notes[2].isSpacer, isFalse);
      expect(r.notes[3].isSpacer, isTrue);
      expect(r.notes[4].isSpacer, isTrue);
      expect(r.notes[5].isSpacer, isFalse);
    });

    test('standalone pipes group surrounded notes', () {
      final r = SolfegeParser.parse('do | re mi fa | sol');
      expect(r.notes.length, 5);
      expect(r.notes[0].groupId, isNull);
      expect(r.notes[1].groupId, isNotNull);
      expect(r.notes[2].groupId, r.notes[1].groupId);
      expect(r.notes[3].groupId, r.notes[1].groupId);
      expect(r.notes[4].groupId, isNull);
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

    test('groups work with lyric/solfège tokens', () {
      final r = SolfegeParser.parse('|twin/do kle/re|');
      expect(r.notes.length, 2);
      expect(r.notes[0].lyric, 'twin');
      expect(r.notes[1].lyric, 'kle');
      expect(r.notes[0].groupId, isNotNull);
      expect(r.notes[0].groupId, r.notes[1].groupId);
    });

    // ── Empty / edge cases ──────────────────────────────────────────────

    test('empty input yields empty result', () {
      final r = SolfegeParser.parse('   ');
      expect(r.notes, isEmpty);
      expect(r.unrecognized, isEmpty);
    });

    test('bare slash is skipped', () {
      final r = SolfegeParser.parse('do / re');
      expect(r.notes.length, 2);
      expect(r.notes[0].syllable, 'do');
      expect(r.notes[1].syllable, 're');
    });

    test('unrecognised solfège portion is reported', () {
      final r = SolfegeParser.parse('Mary/zoop');
      expect(r.notes, isEmpty);
      expect(r.unrecognized, ['Mary/zoop']);
    });
  });

  group('SolfegeParser.isKnownSyllable', () {
    test('recognises bare syllables', () {
      expect(SolfegeParser.isKnownSyllable('do'), isTrue);
      expect(SolfegeParser.isKnownSyllable('sol'), isTrue);
      expect(SolfegeParser.isKnownSyllable('ti'), isTrue);
    });

    test('recognises with octave markers', () {
      expect(SolfegeParser.isKnownSyllable("do'"), isTrue);
      expect(SolfegeParser.isKnownSyllable("do''"), isTrue);
      expect(SolfegeParser.isKnownSyllable("do,"), isTrue);
    });

    test('case-insensitive', () {
      expect(SolfegeParser.isKnownSyllable('DO'), isTrue);
      expect(SolfegeParser.isKnownSyllable('Re'), isTrue);
    });

    test('rejects non-solfège words', () {
      expect(SolfegeParser.isKnownSyllable('Mary'), isFalse);
      expect(SolfegeParser.isKnownSyllable('hello'), isFalse);
      expect(SolfegeParser.isKnownSyllable('doom'), isFalse);
    });
  });
}
