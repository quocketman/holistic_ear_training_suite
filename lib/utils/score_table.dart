/// A structured, table-shaped representation of a whiteboard score.
///
/// The whiteboard's editing surface is a table: columns are beats (left→right
/// in time) and voices are stacked pairs of rows — an UPPER row (lyric or
/// placeholder syllable) and a LOWER row (solfège). Phase 1 exposes a single
/// voice; the model already holds `voiceCount` voices so harmony voices are
/// purely additive.
///
/// This model round-trips losslessly with the existing whitespace/slash text
/// syntax that [SolfegeParser] understands (for a single voice), so the render,
/// export and `#text=` link pipeline is unchanged: the table serializes to that
/// text, and legacy links deserialize back into the table.
library;

import 'dart:math' as math;

import 'solfege_parser.dart';

/// One cell = one voice at one column: the upper text (lyric/placeholder) and
/// the lower solfège token (e.g. "do", "la'", "re,").
class ScoreCell {
  String text; // upper row: lyric or placeholder syllable ('' = none)
  String solfege; // lower row: solfège token ('' = none)

  ScoreCell({this.text = '', this.solfege = ''});

  bool get isEmpty => text.isEmpty && solfege.isEmpty;

  ScoreCell copy() => ScoreCell(text: text, solfege: solfege);
}

/// One column (beat) across all voices, plus structural flags carried over
/// from the legacy syntax (`|` grouping, `[]` line break, `_` spacer).
class ScoreColumn {
  /// One cell per voice; length is kept == [ScoreTable.voiceCount].
  List<ScoreCell> cells;

  /// A `|` cluster box opens at this column and/or closes after it.
  bool groupStart;
  bool groupEnd;

  /// A `[]` line break follows this column (honored by multi-row exports).
  bool breakAfter;

  /// A blank spacer column (`_`) — reserves horizontal space, renders no token.
  bool isSpacer;

  ScoreColumn({
    List<ScoreCell>? cells,
    this.groupStart = false,
    this.groupEnd = false,
    this.breakAfter = false,
    this.isSpacer = false,
  }) : cells = cells ?? [ScoreCell()];

  bool get isBlank =>
      !isSpacer && !breakAfter && cells.every((c) => c.isEmpty);
}

/// The whole score as columns × voices.
class ScoreTable {
  int voiceCount;
  List<ScoreColumn> columns;

  ScoreTable({this.voiceCount = 1, List<ScoreColumn>? columns})
      : columns = columns ?? [];

  /// An empty table with one editable column.
  factory ScoreTable.empty({int voiceCount = 1}) => ScoreTable(
        voiceCount: voiceCount,
        columns: [
          ScoreColumn(cells: List.generate(voiceCount, (_) => ScoreCell())),
        ],
      );

  /// Ensure every column has exactly [voiceCount] cells (pad/trim).
  void normalizeVoices() {
    for (final col in columns) {
      while (col.cells.length < voiceCount) {
        col.cells.add(ScoreCell());
      }
      if (col.cells.length > voiceCount) {
        col.cells.removeRange(voiceCount, col.cells.length);
      }
    }
  }

  ScoreTable copy() => ScoreTable(
        voiceCount: voiceCount,
        columns: columns
            .map((c) => ScoreColumn(
                  cells: c.cells.map((cell) => cell.copy()).toList(),
                  groupStart: c.groupStart,
                  groupEnd: c.groupEnd,
                  breakAfter: c.breakAfter,
                  isSpacer: c.isSpacer,
                ))
            .toList(),
      );

  // ---------------------------------------------------------------------------
  // Serialization to/from the legacy single-voice text syntax.
  // (Multi-voice will move to a Markdown-table encoding; see save-format plan.)
  // ---------------------------------------------------------------------------

  /// Reconstruct a solfège token string ("do", "la'", "re,") from a cell's
  /// pitch. The cell already stores the solfège text directly, so this simply
  /// returns it; kept as a hook for future normalization.
  static String _solfegeToken(ScoreCell cell) => cell.solfege.trim();

  /// Serialize VOICE 0 back to the legacy whitespace/slash text so the existing
  /// parser, canvas, exporters and `#text=` link keep working unchanged.
  String toSolfegeText() {
    final tokens = <String>[];
    for (final col in columns) {
      if (col.groupStart) tokens.add('|');

      if (col.isSpacer) {
        tokens.add('_');
      } else {
        final cell = col.cells.isNotEmpty ? col.cells[0] : ScoreCell();
        final lyric = cell.text.trim();
        final solf = _solfegeToken(cell);
        if (lyric.isNotEmpty && solf.isNotEmpty) {
          tokens.add('$lyric/$solf');
        } else if (lyric.isNotEmpty) {
          // Trailing slash forces lyric-only even if the lyric looks like a
          // syllable (e.g. "do/" → lyric "do").
          tokens.add('$lyric/');
        } else if (solf.isNotEmpty) {
          tokens.add(solf);
        }
        // both empty & not a spacer -> emit nothing (blank column)
      }

      if (col.groupEnd) tokens.add('|');
      if (col.breakAfter) tokens.add('[]');
    }
    return tokens.join(' ');
  }

  /// Build a table from legacy solfège text by parsing it and folding the flat
  /// note list into columns (voice 0). Line breaks/spacers/groups are preserved
  /// as structural flags. Legacy PDF links deserialize through here.
  factory ScoreTable.fromSolfegeText(String text) {
    final result = SolfegeParser.parse(text);
    final columns = <ScoreColumn>[];

    // Column currently accumulating (each pitched/lyric/spacer note = 1 column).
    ScoreColumn? pending;
    void flush() {
      if (pending != null) {
        columns.add(pending!);
        pending = null;
      }
    }

    // Track group runs so we can set groupStart/groupEnd flags.
    int? runGroupId;
    int runStartIndex = -1;
    void closeGroupRun(int endExclusive) {
      if (runGroupId != null && runStartIndex >= 0 && endExclusive > runStartIndex) {
        columns[runStartIndex].groupStart = true;
        columns[endExclusive - 1].groupEnd = true;
      }
      runGroupId = null;
      runStartIndex = -1;
    }

    for (final n in result.notes) {
      if (n.isLineBreak) {
        // Attach the break to the last emitted column (or a fresh blank one).
        flush();
        if (columns.isEmpty) {
          columns.add(ScoreColumn(breakAfter: true));
        } else {
          columns.last.breakAfter = true;
        }
        continue;
      }

      // Group boundary bookkeeping (groups are contiguous same-id runs).
      if (n.groupId != runGroupId) {
        closeGroupRun(columns.length);
        if (n.groupId != null) {
          runGroupId = n.groupId;
          runStartIndex = columns.length;
        }
      }

      flush();
      if (n.isSpacer) {
        columns.add(ScoreColumn(isSpacer: true));
      } else {
        final solf = n.isLyricOnly
            ? ''
            : n.syllable +
                (n.octave > 0 ? "'" * n.octave : '') +
                (n.octave < 0 ? "," * (-n.octave) : '');
        columns.add(ScoreColumn(
          cells: [ScoreCell(text: n.lyric ?? '', solfege: solf)],
        ));
      }
    }
    closeGroupRun(columns.length);
    flush();

    final table = ScoreTable(voiceCount: 1, columns: columns);
    if (table.columns.isEmpty) {
      table.columns.add(ScoreColumn());
    }
    table.normalizeVoices();
    return table;
  }

  // ---------------------------------------------------------------------------
  // Rendering: build the flat note list the canvas/exports consume, directly
  // from the table (all voices), carrying voice + column so the canvas can
  // stack time-aligned voices.
  // ---------------------------------------------------------------------------

  SolfegeParseResult toParseResult() {
    final notes = <SolfegeNote>[];
    final unrecognized = <String>[];
    int? currentGroup;
    var nextGroupId = 0;

    for (var c = 0; c < columns.length; c++) {
      final col = columns[c];
      if (col.groupStart) currentGroup = nextGroupId++;

      if (col.isSpacer) {
        notes.add(SolfegeNote(
          syllable: '_',
          chromaticOffset: 0,
          octave: 0,
          isSpacer: true,
          groupId: currentGroup,
          voice: 0,
          column: c,
        ));
      } else {
        for (var v = 0; v < voiceCount; v++) {
          final cell = v < col.cells.length ? col.cells[v] : ScoreCell();
          final upper = cell.text.trim();
          final solf = cell.solfege.trim();
          if (solf.isNotEmpty) {
            final p = SolfegeParser.parseSolfegeToken(solf);
            if (p == null) {
              unrecognized.add(solf);
              continue;
            }
            notes.add(SolfegeNote(
              syllable: p.syllable,
              chromaticOffset: p.offset,
              octave: p.octave,
              lyric: upper.isEmpty ? null : upper,
              groupId: currentGroup,
              voice: v,
              column: c,
            ));
          } else if (upper.isNotEmpty && v == 0) {
            // Lyric-only (voice 0). A harmony cell with text but no solfège has
            // nothing to pin the placeholder to, so it renders nothing yet.
            notes.add(SolfegeNote(
              syllable: '',
              chromaticOffset: 0,
              octave: 0,
              lyric: upper,
              isLyricOnly: true,
              groupId: currentGroup,
              voice: 0,
              column: c,
            ));
          }
        }
      }

      if (col.groupEnd) currentGroup = null;
      if (col.breakAfter) {
        notes.add(SolfegeNote(
          syllable: '',
          chromaticOffset: 0,
          octave: 0,
          isLineBreak: true,
          column: c,
        ));
      }
    }
    return SolfegeParseResult(notes: notes, unrecognized: unrecognized);
  }

  // ---------------------------------------------------------------------------
  // Markdown save format — a human-readable table encoded into the share link.
  // Columns are beats; two rows per voice (lyric / solfège) plus a `marks` row
  // carrying per-beat structure so pipes never appear inside cells:
  //   `(` group opens · `)` group closes after · `/` line break after ·
  //   `_` spacer · `.` nothing.
  // ---------------------------------------------------------------------------

  static String _markToken(ScoreColumn col) {
    final b = StringBuffer();
    if (col.isSpacer) b.write('_');
    if (col.groupStart) b.write('(');
    if (col.groupEnd) b.write(')');
    if (col.breakAfter) b.write('/');
    return b.isEmpty ? '.' : b.toString();
  }

  String toMarkdown() {
    final beats = columns.length;
    String row(String label, List<String> cells) =>
        '| $label | ${cells.map((c) => c.isEmpty ? ' ' : c).join(' | ')} |';

    final lines = <String>[
      row('part', [for (var i = 0; i < beats; i++) '${i + 1}']),
      '|${List.filled(beats + 1, '---').join('|')}|',
    ];
    for (var v = 0; v < voiceCount; v++) {
      lines.add(row('lyric ${v + 1}', [
        for (final col in columns)
          (col.isSpacer || v >= col.cells.length) ? '' : col.cells[v].text
      ]));
      lines.add(row('solfège ${v + 1}', [
        for (final col in columns)
          (col.isSpacer || v >= col.cells.length) ? '' : col.cells[v].solfege
      ]));
    }
    lines.add(row('marks', [for (final col in columns) _markToken(col)]));
    return lines.join('\n');
  }

  factory ScoreTable.fromMarkdown(String md) {
    List<String> cellsOf(String line) {
      var parts = line.split('|');
      if (parts.isNotEmpty && parts.first.trim().isEmpty) {
        parts = parts.sublist(1);
      }
      if (parts.isNotEmpty && parts.last.trim().isEmpty) {
        parts = parts.sublist(0, parts.length - 1);
      }
      return parts.map((p) => p.trim()).toList();
    }

    final rows = <List<String>>[];
    for (final raw in md.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('|')) continue;
      final cells = cellsOf(line);
      final isSep = cells.isNotEmpty &&
          cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c) || c.isEmpty);
      if (isSep) continue;
      rows.add(cells);
    }
    if (rows.isEmpty) return ScoreTable.empty();

    final byLabel = <String, List<String>>{};
    for (final r in rows) {
      if (r.isEmpty) continue;
      byLabel[r.first.toLowerCase()] = r.sublist(1);
    }

    final beats = rows.first.length - 1;
    var voiceCount = 1;
    for (final label in byLabel.keys) {
      final m = RegExp(r'(?:lyric|solf[eè]ge?)\s*(\d+)').firstMatch(label);
      if (m != null) {
        voiceCount = math.max(voiceCount, int.parse(m.group(1)!));
      }
    }
    final marks = byLabel['marks'] ?? const <String>[];

    String at(List<String> list, int i) =>
        (i < list.length && list[i] != ' ') ? list[i] : '';

    final columns = <ScoreColumn>[];
    for (var c = 0; c < beats; c++) {
      final cells = <ScoreCell>[];
      for (var v = 1; v <= voiceCount; v++) {
        final lyricRow = byLabel['lyric $v'] ?? const <String>[];
        final solfRow =
            byLabel['solfège $v'] ?? byLabel['solfege $v'] ?? const <String>[];
        cells.add(ScoreCell(text: at(lyricRow, c), solfege: at(solfRow, c)));
      }
      final mark = c < marks.length ? marks[c] : '.';
      columns.add(ScoreColumn(
        cells: cells,
        groupStart: mark.contains('('),
        groupEnd: mark.contains(')'),
        breakAfter: mark.contains('/'),
        isSpacer: mark.contains('_'),
      ));
    }

    final table = ScoreTable(voiceCount: voiceCount, columns: columns);
    if (table.columns.isEmpty) table.columns.add(ScoreColumn());
    table.normalizeVoices();
    return table;
  }
}
