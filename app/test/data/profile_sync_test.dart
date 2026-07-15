import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playzy/data/auth/auth_api.dart' show UnauthorizedException;
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/data/profile/profile_sync.dart';
import 'package:playzy/data/profile/profile_sync_api.dart';
import 'package:playzy/domain/child_profile.dart';
import 'package:playzy/domain/story_options.dart';

class FakeProfileSyncApi implements ProfileSyncApi {
  final Map<String, String> docs = {};
  @override
  Future<String?> getDoc(String kind) async => docs[kind];
  @override
  Future<void> putDoc(String kind, String doc) async => docs[kind] = doc;
}

final _profile = ChildProfile(id: 'p1', givenName: '하준', ageBand: AgeBand.values.first);
const _roster = [StoryCharacter(name: '뽀삐', kind: CharacterKind.animal)];

void main() {
  group('ProfileSync.reconcile', () {
    test('adopts the account document when the account already has one', () async {
      final api = FakeProfileSyncApi()
        ..docs['profile'] = _profile.encode()
        ..docs['roster'] = jsonEncode(_roster.map((c) => c.toJson()).toList());
      final repo = FakeProfileRepository(); // local empty
      await ProfileSync(api, repo).reconcile();

      expect((await repo.loadProfile())?.givenName, '하준');
      expect((await repo.loadRoster()).single.name, '뽀삐');
    });

    test('seeds the account from local when the account has none', () async {
      final api = FakeProfileSyncApi(); // account empty
      final repo = FakeProfileRepository();
      await repo.saveProfile(_profile);
      await repo.saveRoster(_roster);

      await ProfileSync(api, repo).reconcile();

      expect(ChildProfile.decode(api.docs['profile']!).givenName, '하준');
      expect(api.docs['roster'], contains('뽀삐'));
    });

    test('does not push an empty local profile/roster', () async {
      final api = FakeProfileSyncApi();
      await ProfileSync(api, FakeProfileRepository()).reconcile();
      expect(api.docs, isEmpty);
    });
  });

  test('pushProfile / pushRoster upload the encoded documents', () async {
    final api = FakeProfileSyncApi();
    final sync = ProfileSync(api, FakeProfileRepository());
    await sync.pushProfile(_profile);
    await sync.pushRoster(_roster);
    expect(ChildProfile.decode(api.docs['profile']!).givenName, '하준');
    expect(api.docs['roster'], contains('뽀삐'));
  });

  group('HttpProfileSyncApi', () {
    test('getDoc returns the doc or null', () async {
      final present = HttpProfileSyncApi(
        baseUrl: 'https://api.test',
        authHeaders: const {'Authorization': 'Bearer t'},
        client: MockClient((req) async {
          expect(req.url.path, '/v1/profile');
          expect(req.headers['Authorization'], 'Bearer t');
          return http.Response(jsonEncode({'doc': '{"x":1}'}), 200);
        }),
      );
      expect(await present.getDoc('profile'), '{"x":1}');

      final absent = HttpProfileSyncApi(
        baseUrl: 'https://api.test',
        authHeaders: const {},
        client: MockClient((_) async => http.Response(jsonEncode({'doc': null}), 200)),
      );
      expect(await absent.getDoc('roster'), isNull);
    });

    test('putDoc sends the doc and accepts 204', () async {
      var sent = '';
      final api = HttpProfileSyncApi(
        baseUrl: 'https://api.test',
        authHeaders: const {},
        client: MockClient((req) async {
          expect(req.method, 'PUT');
          sent = (jsonDecode(req.body) as Map)['doc'] as String;
          return http.Response('', 204);
        }),
      );
      await api.putDoc('profile', '{"y":2}');
      expect(sent, '{"y":2}');
    });

    test('a 401 is an UnauthorizedException', () async {
      final api = HttpProfileSyncApi(
        baseUrl: 'https://api.test',
        authHeaders: const {},
        client: MockClient((_) async => http.Response('', 401)),
      );
      expect(() => api.getDoc('profile'), throwsA(isA<UnauthorizedException>()));
    });
  });
}
