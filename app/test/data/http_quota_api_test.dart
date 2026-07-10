import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playzy/data/quota/quota_api.dart';

void main() {
  group('HttpQuotaApi', () {
    test('fetches quota with the device header', () async {
      late http.Request captured;
      final api = HttpQuotaApi(
        baseUrl: 'https://api.test/',
        deviceId: 'dev1',
        client: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({'freeUsed': 1, 'freeLimit': 3, 'credits': 0, 'canGenerate': true}),
            200,
          );
        }),
      );

      final q = await api.fetchQuota();

      expect(captured.url.toString(), 'https://api.test/v1/quota');
      expect(captured.headers['X-Device-Id'], 'dev1');
      expect(q.freeRemaining, 2);
      expect(q.canGenerate, isTrue);
    });

    test('throws on a non-200 quota response', () async {
      final api = HttpQuotaApi(
        baseUrl: 'https://api.test',
        deviceId: 'dev1',
        client: MockClient((_) async => http.Response('down', 503)),
      );
      expect(api.fetchQuota(), throwsA(isA<Exception>()));
    });

    test('grantCreditsDev posts the amount and admin token', () async {
      late http.Request captured;
      final api = HttpQuotaApi(
        baseUrl: 'https://api.test',
        deviceId: 'dev1',
        client: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({'freeUsed': 3, 'freeLimit': 3, 'credits': 10, 'canGenerate': true}),
            200,
          );
        }),
      );

      final q = await api.grantCreditsDev(10, 'secret');

      expect(captured.url.toString(), 'https://api.test/v1/credits');
      expect(captured.headers['X-Admin-Token'], 'secret');
      expect(jsonDecode(captured.body)['amount'], 10);
      expect(q.credits, 10);
    });
  });
}
