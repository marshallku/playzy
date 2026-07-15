import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playzy/data/auth/auth_api.dart';

void main() {
  group('HttpAuthApi', () {
    test('requestNonce returns the server nonce', () async {
      final api = HttpAuthApi(
        baseUrl: 'https://api.test/',
        client: MockClient((req) async {
          expect(req.url.toString(), 'https://api.test/v1/auth/nonce');
          return http.Response(jsonEncode({'nonce': 'n-123'}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      expect(await api.requestNonce(), 'n-123');
    });

    test('signIn posts to the provider endpoint and parses the session', () async {
      final api = HttpAuthApi(
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          expect(req.url.path, '/v1/auth/google');
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['idToken'], 'id-tok');
          expect(body['nonce'], 'n-1');
          return http.Response(
            jsonEncode({'token': 'sess-tok', 'account': {'id': 'acct_abc'}, 'isNew': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final session = await api.signIn(provider: 'google', idToken: 'id-tok', nonce: 'n-1');
      expect(session.token, 'sess-tok');
      expect(session.accountId, 'acct_abc');
    });

    test('signIn maps 401 to UnauthorizedException', () async {
      final api = HttpAuthApi(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response('{"error":"invalid id token"}', 401)),
      );
      expect(
        () => api.signIn(provider: 'apple', idToken: 'x', nonce: 'y'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('signIn maps other non-2xx to AuthException', () async {
      final api = HttpAuthApi(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response('boom', 500)),
      );
      expect(
        () => api.signIn(provider: 'apple', idToken: 'x', nonce: 'y'),
        throwsA(isA<AuthException>().having((e) => e, 'not unauthorized', isNot(isA<UnauthorizedException>()))),
      );
    });

    test('signIn rejects a malformed success body', () async {
      final api = HttpAuthApi(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response(jsonEncode({'token': ''}), 200)),
      );
      expect(() => api.signIn(provider: 'apple', idToken: 'x', nonce: 'y'), throwsA(isA<AuthException>()));
    });

    test('non-string fields are AuthException, not a raw type error', () async {
      final nonceApi = HttpAuthApi(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response(jsonEncode({'nonce': 123}), 200)),
      );
      expect(() => nonceApi.requestNonce(), throwsA(isA<AuthException>()));

      final signInApi = HttpAuthApi(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response(jsonEncode({'token': 1, 'account': {'id': 2}}), 200)),
      );
      expect(
        () => signInApi.signIn(provider: 'apple', idToken: 'x', nonce: 'y'),
        throwsA(isA<AuthException>()),
      );
    });

    test('deleteAccount sends the bearer token and accepts 204', () async {
      var seenAuth = '';
      final api = HttpAuthApi(
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          expect(req.method, 'DELETE');
          expect(req.url.path, '/v1/me');
          seenAuth = req.headers['authorization'] ?? '';
          return http.Response('', 204);
        }),
      );
      await api.deleteAccount('sess-tok');
      expect(seenAuth, 'Bearer sess-tok');
    });

    test('deleteAccount maps 401 to UnauthorizedException', () async {
      final api = HttpAuthApi(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response('', 401)),
      );
      expect(() => api.deleteAccount('dead'), throwsA(isA<UnauthorizedException>()));
    });

    test('a transport error becomes an AuthException', () async {
      final api = HttpAuthApi(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => throw Exception('offline')),
      );
      expect(() => api.requestNonce(), throwsA(isA<AuthException>()));
    });
  });
}
