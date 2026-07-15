import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/auth_controller.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/auth/auth_api.dart';
import 'package:playzy/data/auth/auth_session.dart';
import 'package:playzy/data/auth/session_store.dart';
import 'package:playzy/data/auth/social_sign_in.dart';
import 'package:playzy/data/payment/fake_payment_gateway.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/domain/child_profile.dart';
import 'package:playzy/domain/story_options.dart';

class FakeAuthApi implements AuthApi {
  AuthSession session = const AuthSession(token: 'tok-1', accountId: 'acct_1');
  String? deletedToken;

  @override
  Future<String> requestNonce() async => 'nonce-1';

  @override
  Future<AuthSession> signIn({required String provider, required String idToken, required String nonce}) async =>
      session;

  @override
  Future<void> fetchMe(String token) async {}

  @override
  Future<void> deleteAccount(String token) async {
    deletedToken = token;
  }
}

class FakeSocialSignIn implements SocialSignIn {
  @override
  Future<SocialCredential> signIn(AuthProviderKind kind, {required String rawNonce}) async =>
      const SocialCredential('id-tok');
}

class FakeSessionStore implements SessionStore {
  FakeSessionStore({this.failWrite = false, this.failClear = false});
  final bool failWrite;
  final bool failClear;
  AuthSession? stored;
  @override
  Future<AuthSession?> read() async => stored;
  @override
  Future<void> write(AuthSession session) async {
    if (failWrite) throw Exception('write failed');
    stored = session;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw Exception('clear failed');
    stored = null;
  }
}

ProviderContainer _container({
  FakeAuthApi? api,
  FakeSessionStore? store,
  FakePaymentGateway? gateway,
  AuthSession? initial,
  FakeProfileRepository? profileRepo,
}) {
  final gw = gateway ?? FakePaymentGateway();
  addTearDown(gw.dispose);
  final c = ProviderContainer(overrides: [
    deviceIdProvider.overrideWithValue('dev-1'),
    authApiProvider.overrideWithValue(api ?? FakeAuthApi()),
    socialSignInProvider.overrideWithValue(FakeSocialSignIn()),
    secureSessionStoreProvider.overrideWithValue(store ?? FakeSessionStore()),
    paymentGatewayProvider.overrideWithValue(gw),
    initialSessionProvider.overrideWithValue(initial),
    profileRepositoryProvider.overrideWithValue(profileRepo ?? FakeProfileRepository()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('AuthController', () {
    test('anonymous headers use X-Device-Id', () {
      final c = _container();
      expect(c.read(authHeadersProvider), {'X-Device-Id': 'dev-1'});
    });

    test('signIn stores the session, aligns payment identity, switches to Bearer', () async {
      final store = FakeSessionStore();
      final gateway = FakePaymentGateway();
      final c = _container(store: store, gateway: gateway);

      await c.read(authControllerProvider.notifier).signIn(AuthProviderKind.google);

      final state = c.read(authControllerProvider);
      expect(state.isSignedIn, isTrue);
      expect(state.accountId, 'acct_1');
      expect(state.identityReady, isTrue);
      expect(store.stored?.token, 'tok-1');
      expect(gateway.lastUserId, 'acct_1'); // RC identity = account
      expect(c.read(authHeadersProvider), {'Authorization': 'Bearer tok-1'});
    });

    test('signOut clears storage and re-aligns payment identity to the device', () async {
      const seeded = AuthSession(token: 't', accountId: 'a');
      final store = FakeSessionStore()..stored = seeded;
      final gateway = FakePaymentGateway();
      final c = _container(store: store, gateway: gateway, initial: seeded);

      await c.read(authControllerProvider.notifier).signOut();

      expect(c.read(authControllerProvider).isSignedIn, isFalse);
      expect(store.stored, isNull);
      expect(gateway.lastUserId, 'dev-1'); // back to the device subject, NOT a fresh anon id
      expect(c.read(authHeadersProvider), {'X-Device-Id': 'dev-1'});
    });

    test('sign-out clears the synced profile/roster so a new user cannot inherit them', () async {
      const seeded = AuthSession(token: 't', accountId: 'a');
      final repo = FakeProfileRepository(
        profile: ChildProfile(id: 'p1', givenName: '하준', ageBand: AgeBand.values.first),
        roster: const [StoryCharacter(name: '뽀삐', kind: CharacterKind.animal)],
      );
      final c = _container(
        store: FakeSessionStore()..stored = seeded,
        initial: seeded,
        profileRepo: repo,
      );

      await c.read(authControllerProvider.notifier).signOut();

      expect(await repo.loadProfile(), isNull, reason: 'profile must be cleared on sign-out');
      expect(await repo.loadRoster(), isEmpty, reason: 'roster must be cleared on sign-out');
    });

    test('deleteAccount calls the backend then signs out', () async {
      final api = FakeAuthApi();
      final c = _container(api: api, initial: const AuthSession(token: 'tok-1', accountId: 'acct_1'));

      await c.read(authControllerProvider.notifier).deleteAccount();

      expect(api.deletedToken, 'tok-1');
      expect(c.read(authControllerProvider).isSignedIn, isFalse);
    });

    test('a sign-in that cannot persist fails and stays anonymous', () async {
      final c = _container(store: FakeSessionStore(failWrite: true));
      await expectLater(
        c.read(authControllerProvider.notifier).signIn(AuthProviderKind.apple),
        throwsA(isA<Exception>()),
      );
      expect(c.read(authControllerProvider).isSignedIn, isFalse);
    });

    test('a sign-out that cannot clear storage fails (no silent re-login next launch)', () async {
      const seeded = AuthSession(token: 't', accountId: 'a');
      final store = FakeSessionStore(failClear: true)..stored = seeded;
      final c = _container(store: store, initial: seeded);
      await expectLater(
        c.read(authControllerProvider.notifier).signOut(),
        throwsA(isA<Exception>()),
      );
      // Consistent state: still signed in AND token still persisted (not a split state).
      expect(c.read(authControllerProvider).isSignedIn, isTrue);
      expect(store.stored, isNotNull);
    });

    test('onUnauthorized signs out only for the current token (stale 401 is ignored)', () async {
      final c = _container(initial: const AuthSession(token: 'tok-1', accountId: 'acct_1'));
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.onUnauthorized('stale-token');
      expect(c.read(authControllerProvider).isSignedIn, isTrue, reason: 'stale token must not sign out');

      await ctrl.onUnauthorized('tok-1');
      expect(c.read(authControllerProvider).isSignedIn, isFalse, reason: 'current token signs out');
    });
  });
}
