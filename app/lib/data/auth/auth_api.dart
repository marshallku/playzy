import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';

/// A recoverable auth failure (network, malformed response, non-2xx).
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => 'AuthException: $message';
}

/// The backend rejected the session/token (401). Callers should return to the
/// anonymous state (sign out) when the failing token is still the current one.
class UnauthorizedException extends AuthException {
  const UnauthorizedException() : super('unauthorized');
}

/// Client for the backend auth endpoints (WU3). The provider sign-in itself (Apple/
/// Google/Kakao SDK) is a separate seam; this only exchanges a verified id_token +
/// server nonce for a Playzy session, and manages the account.
abstract interface class AuthApi {
  /// A fresh single-use login nonce to bind the provider id_token to this attempt.
  Future<String> requestNonce();

  /// Exchanges a provider [idToken] (bound to [nonce]) for a Playzy session.
  /// [provider] is one of "apple" | "google" | "kakao".
  Future<AuthSession> signIn({
    required String provider,
    required String idToken,
    required String nonce,
  });

  /// Validates a stored session (GET /v1/me). Throws [UnauthorizedException] when the
  /// token is rejected (401) and [AuthException] on transport/server errors — so a
  /// caller can discard the session ONLY on a real rejection, not a transient failure.
  Future<void> fetchMe(String token);

  /// Permanently deletes the account behind [token] (DELETE /v1/me).
  Future<void> deleteAccount(String token);
}

class HttpAuthApi implements AuthApi {
  HttpAuthApi({required String baseUrl, http.Client? client})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<String> requestNonce() async {
    final res = await _send(() => _client.post(Uri.parse('$baseUrl/v1/auth/nonce')));
    final nonce = _decode(res)['nonce'];
    if (nonce is! String || nonce.isEmpty) {
      throw const AuthException('empty or malformed nonce');
    }
    return nonce;
  }

  @override
  Future<AuthSession> signIn({
    required String provider,
    required String idToken,
    required String nonce,
  }) async {
    final res = await _send(() => _client.post(
          Uri.parse('$baseUrl/v1/auth/$provider'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'idToken': idToken, 'nonce': nonce}),
        ));
    final body = _decode(res);
    final token = body['token'];
    final account = body['account'];
    final accountId = account is Map<String, dynamic> ? account['id'] : null;
    if (token is! String || token.isEmpty || accountId is! String || accountId.isEmpty) {
      throw const AuthException('malformed sign-in response');
    }
    return AuthSession(token: token, accountId: accountId);
  }

  @override
  Future<void> fetchMe(String token) async {
    await _send(() => _client.get(
          Uri.parse('$baseUrl/v1/me'),
          headers: {'Authorization': 'Bearer $token'},
        ));
  }

  @override
  Future<void> deleteAccount(String token) async {
    await _send(() => _client.delete(
          Uri.parse('$baseUrl/v1/me'),
          headers: {'Authorization': 'Bearer $token'},
        ));
  }

  /// Runs a request, mapping transport errors + 401 + other non-2xx to typed
  /// exceptions. 204/200 are success.
  Future<http.Response> _send(Future<http.Response> Function() call) async {
    late final http.Response res;
    try {
      res = await call();
    } catch (e) {
      throw AuthException('network error: $e');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException();
    }
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw AuthException('auth server ${res.statusCode}');
    }
    return res;
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw AuthException('malformed response: $e');
    }
  }
}
