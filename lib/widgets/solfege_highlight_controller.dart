import 'package:flutter/material.dart';

import '../utils/solfege_parser.dart';

/// A `TextEditingController` that italicises the recognised-solfège portion
/// of each token as the user types. Mirrors the parser's classification
/// rules so the on-screen highlighting matches what the canvas will render:
///
///   `Mary/do`   → "Mary/" plain, "do" italic
///   `do`        → italic (bare known syllable)
///   `do/`       → plain (trailing slash forces lyric)
///   `/do`       → "/" plain, "do" italic
///   `Mary`      → plain (no match)
///   `_` `|`     → plain (parser syntax)
///
/// Italics are applied in the input field only — the canvas itself does
/// not italicise (per the project's visual style decisions).
class SolfegeHighlightController extends TextEditingController {
  SolfegeHighlightController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    if (text.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final children = <InlineSpan>[];
    // Alternating whitespace runs and non-whitespace tokens preserves the
    // exact character positions so cursor/selection arithmetic stays
    // correct.
    final pattern = RegExp(r'(\s+)|(\S+)');
    for (final match in pattern.allMatches(text)) {
      final whitespace = match.group(1);
      if (whitespace != null) {
        children.add(TextSpan(text: whitespace, style: style));
      } else {
        _appendTokenSpans(match.group(2)!, style, children);
      }
    }
    return TextSpan(style: style, children: children);
  }

  // ── Per-token analysis ────────────────────────────────────────────────

  /// Adds spans for a single non-whitespace token. Strips leading/trailing
  /// pipes, hands the core to [_appendCoreSpans], and wraps any pipes in
  /// the plain style.
  void _appendTokenSpans(
      String token, TextStyle? base, List<InlineSpan> out) {
    var start = 0;
    var end = token.length;
    while (start < end && token[start] == '|') {
      start++;
    }
    while (end > start && token[end - 1] == '|') {
      end--;
    }

    if (start > 0) {
      out.add(TextSpan(text: token.substring(0, start), style: base));
    }
    final core = token.substring(start, end);
    if (core.isNotEmpty) {
      _appendCoreSpans(core, base, out);
    }
    if (end < token.length) {
      out.add(TextSpan(text: token.substring(end), style: base));
    }
  }

  /// Handles the pipe-stripped token. Splits on the last `/` (matching the
  /// parser), italicising only the solfège portion when it's a recognised
  /// syllable.
  void _appendCoreSpans(
      String core, TextStyle? base, List<InlineSpan> out) {
    // Spacers, bare slashes, etc. — plain text.
    if (RegExp(r'^[_/]+$').hasMatch(core)) {
      out.add(TextSpan(text: core, style: base));
      return;
    }

    final slash = core.lastIndexOf('/');
    if (slash >= 0) {
      final lyricPart = core.substring(0, slash);
      final solfPart = core.substring(slash + 1);

      out.add(TextSpan(text: lyricPart, style: base));
      out.add(TextSpan(text: '/', style: base));

      if (solfPart.isEmpty) {
        // Trailing slash — lyric forced. Nothing more to render.
        return;
      }
      final solfStyle = SolfegeParser.isKnownSyllable(solfPart)
          ? _italic(base)
          : base;
      out.add(TextSpan(text: solfPart, style: solfStyle));
      return;
    }

    // No slash — italicise iff the whole token is a known syllable.
    final style =
        SolfegeParser.isKnownSyllable(core) ? _italic(base) : base;
    out.add(TextSpan(text: core, style: style));
  }

  TextStyle _italic(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic);
}
