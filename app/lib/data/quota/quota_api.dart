import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/quota_state.dart';
import '../auth/auth_api.dart' show UnauthorizedException;

/// Reads the backend's authoritative quota (ADR 0002). Offline/fake mode does
/// not use this — the app builds [QuotaState] from local mirrors instead.
abstract interface class QuotaApi {
  Future<QuotaState> fetchQuota();

  /// Grants credits server-side. This is a **dev-only** path (the endpoint is
  /// admin-token-gated); in production a verified purchase webhook does this.
  /// Returns the updated state. Throws if no dev admin token is configured.
  Future<QuotaState> grantCreditsDev(int amount, String adminToken);
}

class HttpQuotaApi implements QuotaApi {
  HttpQuotaApi({
    required String baseUrl,
    required this.authHeaders,
    required this.subject,
    http.Client? client,
  })  : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;

  /// Subject headers for the authoritative read: Bearer when signed in, else
  /// X-Device-Id.
  final Map<String, String> authHeaders;

  /// The current subject id (account when signed in, else device) — used only by the
  /// dev admin grant path, which targets X-Device-Id explicitly.
  final String subject;
  final http.Client _client;

  @override
  Future<QuotaState> fetchQuota() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/v1/quota'),
      headers: authHeaders,
    );
    if (res.statusCode == 401) {
      throw const UnauthorizedException();
    }
    if (res.statusCode != 200) {
      throw Exception('quota server ${res.statusCode}');
    }
    return QuotaState.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<QuotaState> grantCreditsDev(int amount, String adminToken) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/v1/credits'),
      headers: {
        'content-type': 'application/json',
        'X-Device-Id': subject,
        'X-Admin-Token': adminToken,
      },
      body: jsonEncode({'amount': amount}),
    );
    if (res.statusCode != 200) {
      throw Exception('credit grant failed ${res.statusCode}');
    }
    return QuotaState.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
