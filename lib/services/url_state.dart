/// Read shareable Whiteboard state from the page URL — only meaningful on
/// the web build. Native targets always return null (no URL to read).
///
/// Encoding scheme: `https://whiteboard.tuneindigo.com/#text=<urlencoded>`
/// where `<urlencoded>` is `Uri.encodeComponent(solfegeText)`. The hash
/// fragment keeps everything client-side — no server roundtrip and no
/// access-log noise.
library;

import 'url_state_native.dart'
    if (dart.library.js_interop) 'url_state_web.dart' as platform;

/// Returns the solfège text encoded in the current page URL's hash, or null
/// if there isn't one (or this isn't the web build). Decoded ready to be
/// dropped straight into the input field.
String? readSolfegeTextFromUrl() => platform.readSolfegeTextFromUrl();

/// Returns the Markdown-table score encoded in the current page URL's hash
/// (`#table=<urlencoded markdown>`), or null if absent. This is the newer,
/// multi-voice save format; [readSolfegeTextFromUrl] remains for legacy
/// single-voice `#text=` links.
String? readTableMarkdownFromUrl() => platform.readTableMarkdownFromUrl();

/// Builds the legacy single-voice share URL (`#text=`). Kept so old PDFs keep
/// working; new links use [buildTableShareUrl].
String buildSolfegeShareUrl(String solfegeText) {
  final encoded = Uri.encodeComponent(solfegeText);
  return 'https://whiteboard.tuneindigo.com/#text=$encoded';
}

/// Builds the share / reopen URL carrying the full multi-voice table as a
/// Markdown table (`#table=<urlencoded markdown>`). The hash fragment stays
/// client-side and has generous length limits.
String buildTableShareUrl(String markdown) {
  final encoded = Uri.encodeComponent(markdown);
  return 'https://whiteboard.tuneindigo.com/#table=$encoded';
}
