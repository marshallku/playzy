import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/story.dart';
import '../auth/auth_api.dart' show UnauthorizedException;
import 'story_api.dart';

/// Talks to the stable Playzy story API (ADR 0001). The backend owns the AI
/// provider and the prompt; the app only sends a provider-agnostic
/// [StoryRequest] and parses a [Story]. The [http.Client] is injected so tests
/// can mock transport.
class HttpStoryApi implements StoryApi {
  HttpStoryApi({required String baseUrl, required this.authHeaders, http.Client? client})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  /// Normalized (no trailing slash) so endpoint concatenation can't yield `//`.
  final String baseUrl;

  /// The subject headers: `Authorization: Bearer` when signed in, else
  /// `X-Device-Id` (ADR 0002 — the backend scopes quota to whichever is present).
  final Map<String, String> authHeaders;
  final http.Client _client;

  @override
  Future<Story> generateStory(StoryRequest request) async {
    final uri = Uri.parse('$baseUrl/v1/stories');
    late final http.Response res;
    try {
      res = await _client.post(
        uri,
        headers: {'content-type': 'application/json', ...authHeaders},
        body: jsonEncode(request.toJson()),
      );
    } catch (e) {
      throw StoryApiException('network error: $e');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException(); // dead session → caller signs out
    }
    if (res.statusCode == 402) {
      throw const StoryQuotaException(); // quota used up → paywall
    }
    if (res.statusCode != 200) {
      throw StoryApiException('server ${res.statusCode}: ${res.body}');
    }
    try {
      // Decode bytes as UTF-8 explicitly — res.body falls back to latin1 when
      // the server omits a charset, which would mangle Korean text.
      final body = utf8.decode(res.bodyBytes);
      return Story.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (e) {
      throw StoryApiException('malformed story response: $e');
    }
  }
}
