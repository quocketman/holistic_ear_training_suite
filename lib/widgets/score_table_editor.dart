import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/score_table.dart';
import 'solfege_hex_token.dart' show SolfegeHexTheme;

/// Table-shaped entry surface for the whiteboard.
///
/// Columns are beats; each voice is a PAIR of rows (upper = lyric/placeholder,
/// lower = solfège). There is NO rule between the two rows of a pair — they
/// read as one voice — and a thicker rule under each solfège row delimits the
/// pairs. Tab / space / hyphen advance to the next column; Enter moves to
/// the next row; Backspace in an empty cell removes the column.
///
/// The editor owns its working [ScoreTable] and reports every change via
/// [onChanged]; the screen serializes that back to the legacy solfège text that
/// drives rendering, export and the share link.
class ScoreTableEditor extends StatefulWidget {
  final ScoreTable initialTable;
  final SolfegeHexTheme theme;
  final ValueChanged<ScoreTable> onChanged;

  const ScoreTableEditor({
    super.key,
    required this.initialTable,
    required this.theme,
    required this.onChanged,
  });

  @override
  State<ScoreTableEditor> createState() => _ScoreTableEditorState();
}

class _ScoreTableEditorState extends State<ScoreTableEditor> {
  late ScoreTable _table;

  // Per-cell controllers/focus, indexed [column][row] where
  // row = voiceIndex*2 + (0 upper / 1 lower).
  final List<List<TextEditingController>> _controllers = [];
  final List<List<FocusNode>> _focus = [];

  int get _rowCount => _table.voiceCount * 2;

  @override
  void initState() {
    super.initState();
    _table = widget.initialTable.copy();
    _table.normalizeVoices();
    if (_table.columns.isEmpty) {
      _table.columns.add(ScoreColumn(
        cells: List.generate(_table.voiceCount, (_) => ScoreCell()),
      ));
    }
    _rebuildControllers();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final col in _controllers) {
      for (final c in col) {
        c.dispose();
      }
    }
    for (final col in _focus) {
      for (final f in col) {
        f.dispose();
      }
    }
    _controllers.clear();
    _focus.clear();
  }

  void _rebuildControllers() {
    _disposeControllers();
    for (var col = 0; col < _table.columns.length; col++) {
      _controllers.add(_makeColumnControllers(col));
      _focus.add(List.generate(_rowCount, (_) => FocusNode()));
    }
  }

  List<TextEditingController> _makeColumnControllers(int col) {
    final column = _table.columns[col];
    return List.generate(_rowCount, (row) {
      final voice = row ~/ 2;
      final isUpper = row.isEven;
      final cell =
          voice < column.cells.length ? column.cells[voice] : ScoreCell();
      return TextEditingController(text: isUpper ? cell.text : cell.solfege);
    });
  }

  // --- model <-> controllers -------------------------------------------------

  void _writeCellFromController(int col, int row) {
    if (col >= _table.columns.length) return;
    final column = _table.columns[col];
    final voice = row ~/ 2;
    if (voice >= column.cells.length) return;
    final value = _controllers[col][row].text;
    if (row.isEven) {
      column.cells[voice].text = value;
    } else {
      column.cells[voice].solfege = value;
    }
  }

  void _notify() => widget.onChanged(_table.copy());

  // --- structural edits ------------------------------------------------------

  ScoreColumn _blankColumn() => ScoreColumn(
        cells: List.generate(_table.voiceCount, (_) => ScoreCell()),
      );

  void _insertColumnAt(int index) {
    _table.columns.insert(index, _blankColumn());
    _controllers.insert(
        index, List.generate(_rowCount, (_) => TextEditingController()));
    _focus.insert(index, List.generate(_rowCount, (_) => FocusNode()));
  }

  void _addVoice() {
    setState(() {
      _table.voiceCount += 1;
      _table.normalizeVoices();
      _rebuildControllers();
    });
    _notify();
  }

  void _removeVoice() {
    if (_table.voiceCount <= 1) return;
    setState(() {
      _table.voiceCount -= 1;
      _table.normalizeVoices();
      _rebuildControllers();
    });
    _notify();
  }

  void _removeColumnAt(int index) {
    if (_table.columns.length <= 1) return; // keep at least one column
    _table.columns.removeAt(index);
    for (final c in _controllers[index]) {
      c.dispose();
    }
    for (final f in _focus[index]) {
      f.dispose();
    }
    _controllers.removeAt(index);
    _focus.removeAt(index);
  }

  // --- navigation ------------------------------------------------------------

  void _focusCell(int col, int row) {
    if (col < 0 || col >= _focus.length) return;
    if (row < 0 || row >= _rowCount) return;
    _focus[col][row].requestFocus();
    // Place caret at end.
    final ctrl = _controllers[col][row];
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
  }

  /// Advance to the next column in the same row, creating one if at the end.
  void _advanceColumn(int col, int row, {String seed = ''}) {
    final nextIndex = col + 1;
    setState(() {
      if (nextIndex >= _table.columns.length) {
        _insertColumnAt(nextIndex);
      }
      if (seed.isNotEmpty) {
        _controllers[nextIndex][row].text = seed;
        _writeCellFromController(nextIndex, row);
      }
    });
    // Focus after the frame so the (possibly new) node exists.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusCell(nextIndex, row));
    _notify();
  }

  void _retreatColumn(int col, int row) {
    if (col > 0) _focusCell(col - 1, row);
  }

  void _moveRow(int col, int row, int delta) {
    final target = row + delta;
    if (target >= 0 && target < _rowCount) {
      _focusCell(col, target);
    } else if (delta > 0) {
      // past the last row -> first row of next column
      _advanceToFirstRowOfNextColumn(col);
    }
  }

  void _advanceToFirstRowOfNextColumn(int col) {
    final nextIndex = col + 1;
    setState(() {
      if (nextIndex >= _table.columns.length) _insertColumnAt(nextIndex);
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusCell(nextIndex, 0));
    _notify();
  }

  // --- key + text handling ---------------------------------------------------

  /// Handle keys the text field itself ignores: Tab, Shift+Tab, and Backspace
  /// in an empty cell. (Space/hyphen are handled in [_onCellChanged] because the
  /// field consumes them as text input.)
  KeyEventResult _onCellKey(int col, int row, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.tab) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (shift) {
        _retreatColumn(col, row);
      } else {
        _advanceColumn(col, row);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.backspace) {
      final ctrl = _controllers[col][row];
      final columnBlank = _table.columns[col].isBlank;
      if (ctrl.text.isEmpty && columnBlank && _table.columns.length > 1) {
        setState(() => _removeColumnAt(col));
        WidgetsBinding.instance.addPostFrameCallback((_) =>
            _focusCell((col - 1).clamp(0, _table.columns.length - 1), row));
        _notify();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Split a typed/pasted string into cell values. Space separates and is
  /// dropped; a hyphen separates but stays ATTACHED to the syllable before it
  /// (so "hal-le-lu-jah" → ["hal-","le-","lu-","jah"], matching lyric
  /// hyphenation like "Twink-/do").
  List<String> _splitIntoCells(String s) {
    final out = <String>[];
    final cur = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '-') {
        cur.write('-');
        out.add(cur.toString());
        cur.clear();
      } else if (ch == ' ') {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    if (cur.isNotEmpty) out.add(cur.toString());
    return out;
  }

  /// Handle text edits. On a space/hyphen delimiter the current cell keeps the
  /// syllable (with a trailing hyphen retained), further chunks flow into new
  /// columns, and focus advances — to a fresh empty cell if the input ended on
  /// a delimiter, else onto the last chunk.
  void _onCellChanged(int col, int row, String value) {
    if (!value.contains('-') && !value.contains(' ')) {
      _writeCellFromController(col, row);
      _notify();
      return;
    }
    final pieces = _splitIntoCells(value);
    final endsWithDelimiter = value.endsWith('-') || value.endsWith(' ');
    var target = col;
    setState(() {
      _controllers[col][row].text = pieces.isNotEmpty ? pieces.first : '';
      _writeCellFromController(col, row);
      for (var i = 1; i < pieces.length; i++) {
        target += 1;
        if (target >= _table.columns.length) _insertColumnAt(target);
        _controllers[target][row].text = pieces[i];
        _writeCellFromController(target, row);
      }
      if (endsWithDelimiter) {
        target += 1;
        if (target >= _table.columns.length) _insertColumnAt(target);
      }
    });
    final focusTarget = target;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusCell(focusTarget, row));
    _notify();
  }

  // --- appearance ------------------------------------------------------------

  bool get _isDark => widget.theme == SolfegeHexTheme.dark;
  Color get _fg => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get _gridLine => _isDark ? Colors.white24 : Colors.black26;
  Color get _thickLine => _isDark ? Colors.white54 : Colors.black45;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rowLabels(),
              for (var col = 0; col < _table.columns.length; col++)
                _columnWidget(col),
              _addColumnButton(),
            ],
          ),
        ),
        _voiceControls(),
      ],
    );
  }

  Widget _voiceControls() {
    final dim = _fg.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _addVoice,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            icon: Icon(Icons.add, size: 16, color: dim),
            label: Text('voice', style: TextStyle(color: dim, fontSize: 12)),
          ),
          if (_table.voiceCount > 1)
            TextButton.icon(
              onPressed: _removeVoice,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              icon: Icon(Icons.remove, size: 16, color: dim),
              label: Text('voice', style: TextStyle(color: dim, fontSize: 12)),
            ),
          const SizedBox(width: 4),
          Text(
            '${_table.voiceCount} ${_table.voiceCount == 1 ? "voice" : "voices"}',
            style: TextStyle(color: _fg.withValues(alpha: 0.4), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _rowLabels() {
    // Small labels down the left edge: "♪"/"solfège"/"lyric" per voice pair.
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var voice = 0; voice < _table.voiceCount; voice++) ...[
            _labelCell(voice == 0 ? 'lyric' : 'text'),
            _labelCell('solfège', divider: true),
          ],
        ],
      ),
    );
  }

  Widget _labelCell(String text, {bool divider = false}) {
    return Container(
      height: _cellHeight,
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        border: Border(
          bottom: divider
              ? BorderSide(color: _thickLine, width: 1.6)
              : BorderSide.none,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(color: _fg.withValues(alpha: 0.5), fontSize: 10),
      ),
    );
  }

  static const double _cellHeight = 28;
  static const double _cellWidth = 62;

  Widget _columnWidget(int col) {
    return Column(
      children: [
        for (var row = 0; row < _rowCount; row++) _cellWidget(col, row),
      ],
    );
  }

  Widget _cellWidget(int col, int row) {
    final isSolfege = row.isOdd;
    // Only the solfège row carries a bottom rule: it separates this voice from
    // the next. Inside a pair the lyric and solfège rows run together.
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) => _onCellKey(col, row, event),
      child: Container(
        width: _cellWidth,
        height: _cellHeight,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: _gridLine, width: 0.6),
            bottom: isSolfege
                ? BorderSide(color: _thickLine, width: 1.6)
                : BorderSide.none,
          ),
        ),
        alignment: Alignment.center,
        child: TextField(
          controller: _controllers[col][row],
          focusNode: _focus[col][row],
          textAlign: TextAlign.center,
          cursorColor: _fg,
          style: TextStyle(
            color: _fg,
            fontSize: 14,
            fontStyle: isSolfege ? FontStyle.italic : FontStyle.normal,
            fontWeight: isSolfege ? FontWeight.w600 : FontWeight.normal,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          ),
          onChanged: (v) => _onCellChanged(col, row, v),
          onSubmitted: (_) => _moveRow(col, row, 1),
        ),
      ),
    );
  }

  Widget _addColumnButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: IconButton(
        tooltip: 'Add beat',
        iconSize: 18,
        icon: Icon(Icons.add, color: _fg.withValues(alpha: 0.6)),
        onPressed: () {
          setState(() => _insertColumnAt(_table.columns.length));
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _focusCell(_table.columns.length - 1, 0));
          _notify();
        },
      ),
    );
  }
}
