import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/quota_state.dart';

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
  HttpQuotaApi({required String baseUrl, required this.deviceId, http.Client? client})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final String deviceId;
  final http.Client _client;

  @override
  Future<QuotaState> fetchQuota() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/v1/quota'),
      headers: {'X-Device-Id': deviceId},
    );
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
        'X-Device-Id': deviceId,
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
