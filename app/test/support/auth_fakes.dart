import 'package:playzy/data/auth/auth_api.dart';
import 'package:playzy/data/auth/auth_session.dart';
import 'package:playzy/data/auth/session_store.dart';
import 'package:playzy/data/auth/social_sign_in.dart';

/// Shared auth fakes for the WU5 UI tests (mirrors the inline fakes in
/// auth_controller_test.dart). The native sign-in seam is faked here so the login
/// screen drives the real controller without any SDK / native config.
class FakeAuthApi implements AuthApi {
  FakeAuthApi(
      {this.session = const AuthSession(token: 'tok-1', accountId: 'acct_1'),
      this.failDelete = false});
  AuthSession session;
  final bool failDelete;
  String? deletedToken;

  @override
  Future<String> requestNonce() async => 'nonce-1';

  @override
  Future<AuthSession> signIn(
          {required String provider,
          required String idToken,
          required String nonce}) async =>
      session;

  @override
  Future<void> fetchMe(String token) async {}

  @override
  Future<void> deleteAccount(String token) async {
    if (failDelete) throw const AuthException('delete failed');
    deletedToken = token;
  }
}

/// Succeeds by default; set [fail] to simulate a cancelled / not-yet-wired provider.
class FakeSocialSignIn implements SocialSignIn {
  FakeSocialSignIn({this.fail = false});
  final bool fail;

  @override
  Future<SocialCredential> signIn(AuthProviderKind kind,
      {required String rawNonce}) async {
    if (fail) throw const AuthException('provider not configured');
    return const SocialCredential('id-tok');
  }
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
