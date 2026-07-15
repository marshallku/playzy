import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_api.dart' show UnauthorizedException;

/// Client for the account-scoped profile/roster documents (WU6). Each document is an
/// opaque JSON string; kind is "profile" or "roster". Bearer-authed via [authHeaders].
abstract interface class ProfileSyncApi {
  /// The stored document for [kind], or null when the account has never synced it.
  Future<String?> getDoc(String kind);

  /// Overwrites the account's document for [kind] (arrival-order-wins).
  Future<void> putDoc(String kind, String doc);
}

class HttpProfileSyncApi implements ProfileSyncApi {
  HttpProfileSyncApi({required String baseUrl, required this.authHeaders, http.Client? client})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final Map<String, String> authHeaders;
  final http.Client _client;

  @override
  Future<String?> getDoc(String kind) async {
    final res = await _client.get(Uri.parse('$baseUrl/v1/$kind'), headers: authHeaders);
    if (res.statusCode == 401) throw const UnauthorizedException();
    if (res.statusCode != 200) throw Exception('profile sync get $kind: ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final doc = body['doc'];
    return doc is String ? doc : null; // null when the account has no document yet
  }

  @override
  Future<void> putDoc(String kind, String doc) async {
    final res = await _client.put(
      Uri.parse('$baseUrl/v1/$kind'),
      headers: {'content-type': 'application/json', ...authHeaders},
      body: jsonEncode({'doc': doc}),
    );
    if (res.statusCode == 401) throw const UnauthorizedException();
    if (res.statusCode != 204) throw Exception('profile sync put $kind: ${res.statusCode}');
  }
}
