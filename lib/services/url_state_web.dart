import 'package:web/web.dart' as web;

/// Reads the value of hash param [key] from the page URL, decoded, or null.
String? _readHashParam(String key) {
  final hash = web.window.location.hash;
  if (hash.isEmpty) return null;
  // hash includes the leading '#'.
  final raw = hash.startsWith('#') ? hash.substring(1) : hash;
  for (final pair in raw.split('&')) {
    final eq = pair.indexOf('=');
    if (eq < 0) continue;
    if (pair.substring(0, eq) != key) continue;
    try {
      return Uri.decodeComponent(pair.substring(eq + 1));
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Reads `#text=<urlencoded>` (legacy single-voice) from the page URL.
String? readSolfegeTextFromUrl() => _readHashParam('text');

/// Reads `#table=<urlencoded markdown>` (multi-voice) from the page URL.
String? readTableMarkdownFromUrl() => _readHashParam('table');
