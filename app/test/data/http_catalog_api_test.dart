import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playzy/data/catalog/http_catalog_api.dart';
import 'package:playzy/sdui/sdui_models.dart';

void main() {
  group('HttpCatalogApi', () {
    test('fetches and parses an SDUI catalog on 200', () async {
      final api = HttpCatalogApi(
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          expect(req.url.toString(), 'https://api.test/v1/catalog/situations');
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'components': [
                {'type': 'section', 'title': '오늘'},
                {
                  'type': 'chip_group',
                  'chips': [
                    {'id': 'bedtime', 'label': '잠자기'},
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final doc = await api.fetchSituationCatalog();
      expect(doc.schemaVersion, 1);
      expect(doc.components.whereType<SduiChipGroup>().single.chips.single.id, 'bedtime');
    });

    test('throws on a non-200 status', () async {
      final api = HttpCatalogApi(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response('down', 503)),
      );
      expect(api.fetchSituationCatalog(), throwsA(isA<Exception>()));
    });
  });
}
