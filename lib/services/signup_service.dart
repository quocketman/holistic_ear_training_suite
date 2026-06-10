import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of a single signup submission.
class SignupResult {
  final bool success;
  final String? errorMessage;
  final bool alreadySubscribed;

  const SignupResult({
    required this.success,
    this.errorMessage,
    this.alreadySubscribed = false,
  });

  factory SignupResult.success({bool alreadySubscribed = false}) =>
      SignupResult(success: true, alreadySubscribed: alreadySubscribed);

  factory SignupResult.error(String message) =>
      SignupResult(success: false, errorMessage: message);
}

/// POSTs email signups to the Cloudflare Worker proxy that fronts Mailchimp.
///
/// The Worker keeps the Mailchimp API key off the client (it's a Cloudflare
/// secret) and handles CORS so the SPA at whiteboard.tuneindigo.com can talk
/// to it directly. Worker source: `workers/signup-worker.js`.
class SignupService {
  // Cloudflare Worker that proxies signups to Mailchimp. Deployed 2026-06-10.
  // Source: workers/signup-worker.js.
  static const String _endpoint =
      'https://whiteboard-signup.hans-c60.workers.dev/';

  /// Tag applied to every signup from this surface. Mailchimp will create
  /// the tag automatically if it doesn't exist.
  static const String _defaultTag = 'whiteboard lead';

  /// Whether the endpoint has been configured. Kept as a hook in case we
  /// ever need a kill switch; currently always true.
  static bool get endpointConfigured => !_endpoint.contains('REPLACE-ME');

  static Future<SignupResult> subscribe(
    String email, {
    String tag = _defaultTag,
  }) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || !RegExp(r'^.+@.+\..+$').hasMatch(trimmed)) {
      return SignupResult.error('Please enter a valid email');
    }

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': trimmed,
              'tags': [tag],
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SignupResult.success(
          alreadySubscribed: data['message'] == 'already_subscribed',
        );
      }

      final data = _safeDecode(response.body);
      return SignupResult.error(
        data['error']?.toString() ?? 'Something went wrong. Try again.',
      );
    } catch (_) {
      return SignupResult.error('Network error. Check your connection.');
    }
  }

  static Map<String, dynamic> _safeDecode(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    return {};
  }
}
