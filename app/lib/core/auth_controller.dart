import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/auth/auth_api.dart';
import '../data/auth/auth_session.dart';
import '../data/auth/session_store.dart';
import '../data/auth/social_sign_in.dart';
import 'env.dart';
import 'providers.dart';

/// Auth state for the app. [identityReady] means the payment provider's user id has
/// been aligned with the current subject (account when signed in, device when
/// anonymous) — purchasing should stay fail-closed until it is true (WU5b gate).
class AuthState {
  const AuthState({this.session, this.identityReady = false});

  final AuthSession? session;
  final bool identityReady;

  bool get isSignedIn => session != null;
  String? get token => session?.token;
  String? get accountId => session?.accountId;

  AuthState copyWith({AuthSession? session, bool clearSession = false, bool? identityReady}) =>
      AuthState(
        session: clearSession ? null : (session ?? this.session),
        identityReady: identityReady ?? this.identityReady,
      );
}

/// Secure (Keychain) session store. Overridden with a fake in tests.
final secureSessionStoreProvider =
    Provider<SessionStore>((ref) => SecureSessionStore(const FlutterSecureStorage()));

/// Backend auth client — non-null only when a backend is configured.
final authApiProvider =
    Provider<AuthApi?>((ref) => Env.hasBackend ? HttpAuthApi(baseUrl: Env.apiBaseUrl) : null);

/// Native provider sign-in. Real SDK impls land in WU5b; until then the button flow
/// isn't wired, so the placeholder is never invoked.
final socialSignInProvider = Provider<SocialSignIn>((ref) => const UnsupportedSocialSignIn());

/// The session hydrated in main() (read from secure storage + validated) before the
/// first frame, so [authHeadersProvider] is correct immediately. Overridden in main().
final initialSessionProvider = Provider<AuthSession?>((ref) => null);

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// The per-request auth headers: a Bearer session when signed in, else the anonymous
/// X-Device-Id. Rebuilds when the auth state changes, so the HTTP clients re-key.
final authHeadersProvider = Provider<Map<String, String>>((ref) {
  final session = ref.watch(authControllerProvider).session;
  if (session != null) {
    return {'Authorization': 'Bearer ${session.token}'};
  }
  return {'X-Device-Id': ref.watch(deviceIdProvider)};
});

/// Owns sign-in / sign-out / delete. Transitions are serialized (an overlapping call
/// waits) and ordered so backend auth + payment identity + local storage never end up
/// disagreeing.
class AuthController extends Notifier<AuthState> {
  Future<void> _tail = Future<void>.value();

  @override
  AuthState build() {
    // The gateway is constructed with the hydrated subject (account when a session was
    // restored, else device), so the payment identity already matches the backend
    // subject at startup — identity is ready without a transition. It only flips to
    // false transiently mid sign-in/out until setUserId completes.
    return AuthState(session: ref.read(initialSessionProvider), identityReady: true);
  }

  /// Serializes an operation behind any in-flight one.
  Future<T> _serialize<T>(Future<T> Function() op) async {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await prev.catchError((_) {});
    try {
      return await op();
    } finally {
      done.complete();
    }
  }

  Future<void> signIn(AuthProviderKind kind) => _serialize(() => _signIn(kind));

  Future<void> _signIn(AuthProviderKind kind) async {
    final api = ref.read(authApiProvider);
    if (api == null) {
      throw const AuthException('sign-in requires a backend');
    }
    final nonce = await api.requestNonce();
    final cred = await ref.read(socialSignInProvider).signIn(kind, rawNonce: nonce);
    final session = await api.signIn(provider: kind.name, idToken: cred.idToken, nonce: nonce);

    // Persist FIRST and do NOT swallow a write failure: publishing a signed-in state
    // that didn't persist would silently drop the session on the next launch. If the
    // write fails, sign-in fails and we stay anonymous (RC untouched) — consistent.
    await ref.read(secureSessionStoreProvider).write(session);
    // Align payment identity to the account (best-effort — a RC failure must not
    // block an already-persisted sign-in; identityReady tracks whether it succeeded).
    final identityReady = await _setPaymentIdentity(session.accountId);
    state = AuthState(session: session, identityReady: identityReady);
    _refreshQuota();
  }

  Future<void> signOut() => _serialize(_signOut);

  Future<void> _signOut() async {
    // Clearing the persisted session MUST succeed — a swallowed failure would leave
    // the token on disk and silently sign the user back in on the next launch. If it
    // throws, sign-out fails (state stays as-is, consistent with storage) and the
    // caller can retry.
    await ref.read(secureSessionStoreProvider).clear();
    state = const AuthState(session: null);
    // Re-align payment identity to the device (best-effort — a RC failure must not
    // undo the completed local sign-out).
    final identityReady = await _setPaymentIdentity(ref.read(deviceIdProvider));
    state = state.copyWith(identityReady: identityReady);
    _refreshQuota();
  }

  Future<void> deleteAccount() => _serialize(() async {
        final api = ref.read(authApiProvider);
        final token = state.token;
        if (api != null && token != null) {
          await api.deleteAccount(token);
        }
        await _signOut();
      });

  /// Called by an authed request that got a 401. Token-scoped: it only signs out if
  /// the failing token is STILL the current session, so a stale response from a
  /// superseded token can't tear down a newer sign-in.
  Future<void> onUnauthorized(String token) => _serialize(() async {
        if (state.session?.token == token) {
          await _signOut();
        }
      });

  /// Returns whether the payment identity was aligned to [subject] (best-effort).
  Future<bool> _setPaymentIdentity(String subject) async {
    try {
      await ref.read(paymentGatewayProvider).setUserId(subject);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _refreshQuota() {
    ref.invalidate(quotaStateProvider);
    ref.invalidate(creditsProvider);
  }
}
