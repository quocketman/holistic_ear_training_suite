import 'package:web/web.dart' as web;

/// Reads `#text=<urlencoded>` from the page URL and returns the decoded
/// string, or null if absent / malformed.
String? readSolfegeTextFromUrl() {
  final hash = web.window.location.hash;
  if (hash.isEmpty) return null;
  // hash includes the leading '#'.
  final raw = hash.startsWith('#') ? hash.substring(1) : hash;
  for (final pair in raw.split('&')) {
    final eq = pair.indexOf('=');
    if (eq < 0) continue;
    final key = pair.substring(0, eq);
    if (key != 'text') continue;
    try {
      return Uri.decodeComponent(pair.substring(eq + 1));
    } catch (_) {
      return null;
    }
  }
  return null;
}
