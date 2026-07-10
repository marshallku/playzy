import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../sdui/sdui_models.dart';
import 'catalog_api.dart';

/// Fetches the situation-picker SDUI document from the Playzy backend (ADR
/// 0003). Parse/transport failures are thrown; the provider layer falls back to
/// the bundled catalog so the picker is never empty.
class HttpCatalogApi implements CatalogApi {
  HttpCatalogApi({required String baseUrl, http.Client? client})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  /// Normalized (no trailing slash) so endpoint concatenation can't yield `//`.
  final String baseUrl;
  final http.Client _client;

  @override
  Future<SduiDocument> fetchSituationCatalog() async {
    final uri = Uri.parse('$baseUrl/v1/catalog/situations');
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception('catalog server ${res.statusCode}');
    }
    // Decode as UTF-8 explicitly (res.body defaults to latin1 without charset).
    return SduiDocument.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
