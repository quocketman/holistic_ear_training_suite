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

/// Builds the share / reopen URL that, when visited, will pre-populate the
/// Whiteboard's input with [solfegeText]. Always returns the public
/// production URL — same string works whether called from web or native.
String buildSolfegeShareUrl(String solfegeText) {
  final encoded = Uri.encodeComponent(solfegeText);
  return 'https://whiteboard.tuneindigo.com/#text=$encoded';
}
