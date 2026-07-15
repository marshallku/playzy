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

  AuthState copyWith(
          {AuthSession? session,
          bool clearSession = false,
          bool? identityReady}) =>
      AuthState(
        session: clearSession ? null : (session ?? this.session),
        identityReady: identityReady ?? this.identityReady,
      );
}

/// Secure (Keychain) session store. Overridden with a fake in tests.
final secureSessionStoreProvider = Provider<SessionStore>(
    (ref) => SecureSessionStore(const FlutterSecureStorage()));

/// Backend auth client — non-null only when a backend is configured.
final authApiProvider = Provider<AuthApi?>((ref) => Env.hasBackend
    ? HttpAuthApi(
        baseUrl: Env.apiBaseUrl, client: ref.watch(httpClientProvider))
    : null);

/// Native provider sign-in. Real SDK impls land in WU5b; until then the button flow
/// isn't wired, so the placeholder is never invoked.
final socialSignInProvider =
    Provider<SocialSignIn>((ref) => const UnsupportedSocialSignIn());

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
    final initial = ref.read(initialSessionProvider);
    if (initial != null) {
      // A returning signed-in user is already authenticated without calling signIn(),
      // so reconcile their profile/roster once at startup too (best-effort). Run it
      // through _serialize so it can't interleave with a sign-out — otherwise a
      // reconcile write could land after sign-out cleared the docs (cross-account
      // leak). The token guard remains as defense in depth.
      Future.microtask(() => _serialize(_syncProfilesAfterLogin));
    }
    return AuthState(session: initial, identityReady: true);
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
    final cred =
        await ref.read(socialSignInProvider).signIn(kind, rawNonce: nonce);
    final session = await api.signIn(
        provider: kind.name, idToken: cred.idToken, nonce: nonce);

    // Persist FIRST and do NOT swallow a write failure: publishing a signed-in state
    // that didn't persist would silently drop the session on the next launch. If the
    // write fails, sign-in fails and we stay anonymous (RC untouched) — consistent.
    await ref.read(secureSessionStoreProvider).write(session);
    // Align payment identity to the account (best-effort — a RC failure must not
    // block an already-persisted sign-in; identityReady tracks whether it succeeded).
    final identityReady = await _setPaymentIdentity(session.accountId);
    state = AuthState(session: session, identityReady: identityReady);
    _refreshQuota();
    await _syncProfilesAfterLogin();
  }

  /// Pulls the account's profile/roster (or seeds them from local) on login, then
  /// refreshes the profile/roster views. Best-effort — a sync failure never fails an
  /// otherwise-successful sign-in.
  Future<void> _syncProfilesAfterLogin() async {
    // Capture the session this reconcile is for; if a sign-out/switch happens while the
    // GET is in flight, the guard stops it from writing the old account's data back.
    final token = state.session?.token;
    try {
      if (token != null) {
        await ref
            .read(profileSyncProvider)
            ?.reconcile(() => state.session?.token == token);
      }
    } catch (_) {}
    ref.invalidate(profileControllerProvider);
    ref.invalidate(rosterControllerProvider);
  }

  Future<void> signOut() => _serialize(_signOut);

  Future<void> _signOut() async {
    // Clearing the persisted session MUST succeed — a swallowed failure would leave
    // the token on disk and silently sign the user back in on the next launch. If it
    // throws, sign-out fails (state stays as-is, consistent with storage) and the
    // caller can retry.
    // Clear the account's synced profile/roster FIRST and REQUIRE it: a swallowed
    // failure would let the next (possibly different) user inherit the prior account's
    // data (cross-account leak). Doing it before the session clear means a failure
    // fails sign-out while the user is still signed in with their own data — a
    // consistent state to retry from, not a leak.
    //
    // KNOWN v1 LIMITATION: the local cache is device-global, so a profile/roster edit
    // that lands in the exact instant between this clear and a subsequent user's
    // session can, in theory, repopulate it. Closing that fully needs ACCOUNT-SCOPED
    // local storage (namespacing the cache by subject) — a follow-up beyond this unit.
    // This clear covers the realistic leaks (signed-out→anonymous, next-user sign-in).
    await ref.read(profileRepositoryProvider).clearSyncedDocs();
    await ref.read(secureSessionStoreProvider).clear();
    state = const AuthState(session: null);
    ref.invalidate(profileControllerProvider);
    ref.invalidate(rosterControllerProvider);
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
          // A backend delete that throws (network/5xx) stops here — stay signed in so
          // the user can retry; nothing local is torn down yet.
          await api.deleteAccount(token);
        }
        // Local teardown uses the SAME required-clears semantics as sign-out: both the
        // synced-doc clear (leak safety — a lingering doc must never seed a later
        // account) and the session clear (no restored token) MUST succeed. If either
        // fails, delete fails loud and the account screen surfaces it for retry; the
        // transient "backend-deleted but still locally signed in" state self-heals via
        // the token-scoped 401 handler and main()'s _hydrateSession (GET /v1/me → 401 →
        // discard). A best-effort force-signed-out was rejected in review: swallowing
        // the clears would weaken leak safety and could restore the token on a
        // 5xx/offline launch.
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
