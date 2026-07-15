import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth/auth_api.dart' show UnauthorizedException;
import '../data/catalog/catalog_api.dart';
import '../data/catalog/http_catalog_api.dart';
import '../data/library/story_library.dart';
import '../data/payment/apple_payment_gateway.dart';
import '../data/payment/fake_payment_gateway.dart';
import '../data/payment/payment_gateway.dart';
import '../data/payment/rc_client.dart';
import '../data/profile/profile_repository.dart';
import '../data/profile/profile_sync.dart';
import '../data/profile/profile_sync_api.dart';
import '../data/quota/quota_api.dart';
import '../data/story/fake_story_api.dart';
import '../data/story/http_story_api.dart';
import '../data/story/story_api.dart';
import '../domain/child_profile.dart';
import '../domain/quota_state.dart';
import '../domain/story.dart';
import '../domain/story_options.dart';
import '../sdui/sdui_models.dart';
import 'auth_controller.dart';
import 'constants.dart';
import 'env.dart';

/// Composition root. Providers wire concrete implementations; tests override
/// them with fakes (ADR 0004). Swapping the AI backend or payment provider is a
/// one-line change here — no call-site edits.

/// Bound in main() after async init via ProviderScope overrides.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override sharedPreferencesProvider in main()'),
);

/// Stable per-install id for the backend's authoritative quota (ADR 0002).
/// Generated and persisted in main(); overridden into the scope there.
final deviceIdProvider = Provider<String>(
  (ref) => throw UnimplementedError('override deviceIdProvider in main()'),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => PrefsProfileRepository(ref.watch(sharedPreferencesProvider)),
);

/// One shared HTTP client for all backend clients, closed on dispose. The api
/// providers rebuild on auth changes; sharing this avoids leaking a client per
/// rebuild (codex review).
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Local library of generated stories (planning/40). Backed by prefs; tests
/// override with a fake.
final storyLibraryProvider = Provider<StoryLibrary>(
  (ref) => PrefsStoryLibrary(ref.watch(sharedPreferencesProvider)),
);

/// Recent stories, most-recent-first, for the home library section. Refreshed
/// after each successful generation.
final recentStoriesProvider =
    FutureProvider<List<Story>>((ref) => ref.watch(storyLibraryProvider).recent());

// Real backend when configured (--dart-define=PLAYZY_API_BASE_URL), else the
// fake so the app runs with no server (ADR 0001).
final storyApiProvider = Provider<StoryApi>((ref) => Env.hasBackend
    ? HttpStoryApi(baseUrl: Env.apiBaseUrl, authHeaders: ref.watch(authHeadersProvider), client: ref.watch(httpClientProvider))
    : const FakeStoryApi());

/// How a purchased credit pack is settled into the authoritative balance. Derived
/// once here so the gateway selection and the paywall's post-purchase handling can
/// never disagree (a real Apple purchase must be settled by the webhook, never a
/// local grant — ADR 0002).
enum PaymentMode {
  /// No backend: the credit balance is a local offline mirror.
  offlineLocal,

  /// Real Apple IAP via RevenueCat; the verified webhook credits the backend.
  appleWebhook,

  /// Backend present with a dev admin token: grant server credits directly (dev).
  devAdmin,

  /// Backend present but no path to grant credits in this build.
  unavailable,
}

final paymentModeProvider = Provider<PaymentMode>((ref) {
  if (!Env.hasBackend) return PaymentMode.offlineLocal;
  // Real Apple IAP requires iOS + a RevenueCat key AND a backend to redeem into
  // (fail closed: never grant locally after a real-money purchase).
  if (!kIsWeb && Platform.isIOS && Env.hasRevenueCat) return PaymentMode.appleWebhook;
  if (Env.hasDevAdminToken) return PaymentMode.devAdmin;
  return PaymentMode.unavailable;
});

final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  if (ref.watch(paymentModeProvider) == PaymentMode.appleWebhook) {
    final rc = RevenueCatClient();
    ref.onDispose(rc.dispose);
    return ApplePaymentGateway(
      rc,
      apiKey: Env.revenueCatIosKey,
      // The initial subject: the account when a session was hydrated at startup, else
      // the device. Read once — auth transitions call gateway.setUserId, so the
      // gateway instance is stable (never reconfigured).
      appUserId: ref.read(authControllerProvider).accountId ?? ref.watch(deviceIdProvider),
    );
  }
  final gateway = FakePaymentGateway();
  ref.onDispose(gateway.dispose);
  return gateway;
});

final catalogApiProvider = Provider<CatalogApi>((ref) =>
    Env.hasBackend ? HttpCatalogApi(baseUrl: Env.apiBaseUrl) : const FakeCatalogApi());

/// Backend quota client — non-null only in backend mode. When null, quota is
/// built from local mirrors (ADR 0002).
final quotaApiProvider = Provider<QuotaApi?>((ref) => Env.hasBackend
    ? HttpQuotaApi(
        baseUrl: Env.apiBaseUrl,
        authHeaders: ref.watch(authHeadersProvider),
        subject: ref.watch(authControllerProvider).accountId ?? ref.watch(deviceIdProvider),
        client: ref.watch(httpClientProvider),
      )
    : null);

/// The situation-picker SDUI document. Falls back to the bundled default if the
/// fetch fails, the schema is newer than supported, OR the document has no
/// usable chips — so the picker is never empty (ADR 0003).
final situationCatalogProvider = FutureProvider<SduiDocument>((ref) async {
  try {
    final doc = await ref.watch(catalogApiProvider).fetchSituationCatalog();
    if (doc.schemaVersion > SduiDocument.supportedVersion || !_hasUsableChips(doc)) {
      return bundledSituationCatalog();
    }
    return doc;
  } catch (_) {
    return bundledSituationCatalog();
  }
});

bool _hasUsableChips(SduiDocument doc) =>
    doc.components.whereType<SduiChipGroup>().any((g) => g.chips.isNotEmpty);

/// Account-scoped profile/roster sync (WU6) — non-null only when signed in with a
/// backend. Reconcile-on-login lives in the AuthController; here it drives push-on-edit.
final profileSyncProvider = Provider<ProfileSync?>((ref) {
  final signedIn = ref.watch(authControllerProvider).session != null;
  if (!Env.hasBackend || !signedIn) return null;
  return ProfileSync(
    HttpProfileSyncApi(baseUrl: Env.apiBaseUrl, authHeaders: ref.watch(authHeadersProvider), client: ref.watch(httpClientProvider)),
    ref.watch(profileRepositoryProvider),
  );
});

/// The child profile (null until set up). Loads on build; [save] persists.
class ProfileController extends AsyncNotifier<ChildProfile?> {
  @override
  Future<ChildProfile?> build() => ref.watch(profileRepositoryProvider).loadProfile();

  /// Persists the profile. Rethrows on a LOCAL save failure so the caller can surface
  /// an error and NOT treat a failed save as success. The backend push is best-effort
  /// (never fails a completed local save). NOTE: a dropped push leaves the edit
  /// local-only until the next successful edit-push; a login before that adopts the
  /// account's older copy (account-wins) and loses the edit — a v1 limitation (a
  /// per-doc revision + retry is a future add).
  Future<void> save(ChildProfile profile) async {
    state = const AsyncLoading();
    try {
      await ref.read(profileRepositoryProvider).saveProfile(profile);
      state = AsyncData(profile);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
    try {
      await ref.read(profileSyncProvider)?.pushProfile(profile);
    } catch (_) {}
  }
}

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, ChildProfile?>(ProfileController.new);

/// The reusable character roster (보관함). Loads on build (seeding once from the
/// legacy companion); [add]/[remove] persist. Mutations are serialized through a
/// pending-future chain so a rapid double-tap can't let an older write land last
/// and clobber the newer full list (codex WU3 C1).
class RosterController extends AsyncNotifier<List<StoryCharacter>> {
  Future<void> _pending = Future.value();

  @override
  Future<List<StoryCharacter>> build() =>
      ref.watch(profileRepositoryProvider).loadRoster();

  /// Runs [op] after any in-flight mutation completes, so state reads and writes
  /// stay ordered. A failed op doesn't break the chain for the next one.
  Future<void> _enqueue(Future<void> Function() op) {
    final next = _pending.then((_) => op());
    _pending = next.catchError((_) {});
    return next;
  }

  /// Adds a character; no-op on a blank name, an existing (name, kind) duplicate,
  /// or once the roster is full. Names are compared trimmed (no case folding —
  /// Korean is caseless; exact match keeps it predictable).
  Future<void> add(StoryCharacter character) => _enqueue(() async {
        final name = character.name.trim();
        if (name.isEmpty) return;
        // Await the initial load so an add fired before loadRoster() resolves
        // can't persist [new] over the real roster (codex WU4 C1).
        final current = await future;
        final duplicate =
            current.any((c) => c.name.trim() == name && c.kind == character.kind);
        if (duplicate || current.length >= AppConstants.maxRosterCharacters) return;
        final next = [...current, StoryCharacter(name: name, kind: character.kind)];
        state = AsyncData(next);
        await ref.read(profileRepositoryProvider).saveRoster(next);
        await _push(next);
      });

  Future<void> remove(StoryCharacter character) => _enqueue(() async {
        final current = await future;
        final next = current
            .where((c) => !(c.name == character.name && c.kind == character.kind))
            .toList();
        state = AsyncData(next);
        await ref.read(profileRepositoryProvider).saveRoster(next);
        await _push(next);
      });

  /// Best-effort backend push of the roster (never fails a completed local save). Same
  /// v1 limitation as ProfileController.save: a dropped push can be lost to
  /// account-wins reconciliation on a later login.
  Future<void> _push(List<StoryCharacter> roster) async {
    try {
      await ref.read(profileSyncProvider)?.pushRoster(roster);
    } catch (_) {}
  }
}

final rosterControllerProvider =
    AsyncNotifierProvider<RosterController, List<StoryCharacter>>(RosterController.new);

/// Free-tier generation counter (local mirror of backend-enforced quota).
class GeneratedCountController extends AsyncNotifier<int> {
  @override
  Future<int> build() => ref.watch(profileRepositoryProvider).generatedCount();

  Future<void> increment() async {
    await ref.read(profileRepositoryProvider).incrementGeneratedCount();
    ref.invalidateSelf();
    await future;
  }

  Future<void> decrement() async {
    await ref.read(profileRepositoryProvider).decrementGeneratedCount();
    ref.invalidateSelf();
    await future;
  }
}

final generatedCountProvider =
    AsyncNotifierProvider<GeneratedCountController, int>(GeneratedCountController.new);

/// Paid credit balance (local mirror of backend-owned balance — ADR 0002).
class CreditsController extends AsyncNotifier<int> {
  @override
  Future<int> build() => ref.watch(profileRepositoryProvider).credits();

  Future<void> add(int amount) async {
    await ref.read(profileRepositoryProvider).addCredits(amount);
    ref.invalidateSelf();
    await future;
  }

  Future<void> consume() async {
    await ref.read(profileRepositoryProvider).consumeCredit();
    ref.invalidateSelf();
    await future;
  }
}

final creditsProvider =
    AsyncNotifierProvider<CreditsController, int>(CreditsController.new);

/// Active durable entitlements, following the gateway's change stream.
final entitlementsProvider = StreamProvider<Set<String>>((ref) async* {
  final gateway = ref.watch(paymentGatewayProvider);
  yield await gateway.activeEntitlements();
  yield* gateway.entitlementChanges();
});

/// The user's story allowance — the ONE shape the UI reads (home count, gating,
/// paywall). Backend mode fetches the authoritative `/v1/quota`; offline mode
/// builds it from local mirrors. Refreshed after each backend generation.
final quotaStateProvider = FutureProvider<QuotaState>((ref) async {
  final api = ref.watch(quotaApiProvider);
  if (api != null) {
    return api.fetchQuota(); // backend is authoritative (ADR 0002)
  }
  final count = await ref.watch(generatedCountProvider.future);
  final credits = await ref.watch(creditsProvider.future);
  final entitlements = await ref.watch(entitlementsProvider.future);
  final hasPro = entitlements.contains(AppConstants.proEntitlement);
  return QuotaState(
    freeUsed: count,
    freeLimit: AppConstants.freeStoryLimit,
    credits: credits,
    canGenerate: hasPro || count < AppConstants.freeStoryLimit || credits > 0,
  );
});

/// Whether the user may generate another story. **Fails closed while quota is
/// loading or errored** so it can't be bypassed during hydration (ADR 0002).
final canGenerateProvider = Provider<bool>(
    (ref) => ref.watch(quotaStateProvider).valueOrNull?.canGenerate ?? false);

/// Thrown when generation is attempted beyond the quota. The controller
/// enforces the gate itself — the UI check is a convenience, not the guard.
class QuotaExceededException implements Exception {
  const QuotaExceededException();
  @override
  String toString() => 'QuotaExceededException: free limit reached';
}

/// What a generation was charged against, so it can be rolled back on failure.
enum _Charge { pro, free, credit }

/// Generates a story with **reserve-then-generate**: the quota is consumed
/// up front and refunded if generation fails, so a failed call is never
/// charged (ADR 0002 — the backend is the transactional source of truth in
/// production; this is the client-side mirror's best-effort equivalent).
class StoryController extends AsyncNotifier<Story?> {
  bool _inFlight = false;

  @override
  Future<Story?> build() async => null;

  Future<Story> generate(StoryRequest request) async {
    // Serialize generations so a rapid double-submit can't both pass the gate.
    if (_inFlight) throw const QuotaExceededException();
    if (!ref.read(canGenerateProvider)) throw const QuotaExceededException();
    _inFlight = true;
    state = const AsyncLoading();
    try {
      final story = ref.read(quotaApiProvider) != null
          ? await _generateViaBackend(request)
          : await _generateLocal(request);
      // Persist AFTER a successful generation, best-effort: a library-save
      // failure must never fail generation or re-charge quota (ADR 0002 / C3).
      await _saveToLibrary(story);
      state = AsyncData(story);
      return story;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    } finally {
      _inFlight = false;
    }
  }

  /// Backend mode: the server reserves/charges and returns 402 (mapped to
  /// [StoryQuotaException]) when exhausted. Refresh the authoritative quota on
  /// EVERY attempt — success or failure — so gating/home never show stale
  /// allowance after a 402.
  Future<Story> _generateViaBackend(StoryRequest request) async {
    // Snapshot the token this request uses BEFORE awaiting, so a concurrent sign-in
    // that replaces the session mid-flight can't cause a stale 401 to sign out the
    // NEW session (onUnauthorized is token-scoped against this snapshot).
    final requestToken = ref.read(authControllerProvider).token;
    try {
      return await ref.read(storyApiProvider).generateStory(request);
    } on UnauthorizedException {
      // The session died mid-use — sign out (only if this request's token is still
      // current) so the app falls back to anonymous, then surface the failure.
      if (requestToken != null) {
        await ref.read(authControllerProvider.notifier).onUnauthorized(requestToken);
      }
      rethrow;
    } finally {
      ref.invalidate(quotaStateProvider);
    }
  }

  /// Best-effort persistence to the local library. Swallows failures (incl. a
  /// missing store) so a save error can't fail an already-successful, already-
  /// charged generation — the story is still returned/shown (C3).
  Future<void> _saveToLibrary(Story story) async {
    try {
      await ref.read(storyLibraryProvider).save(story);
      ref.invalidate(recentStoriesProvider);
    } catch (_) {
      // Story stays visible in the reader; it just may not join the library.
    }
  }

  /// Offline mode: reserve-then-generate against the local mirror, refunding on
  /// failure so a failed call is never charged.
  Future<Story> _generateLocal(StoryRequest request) async {
    final charge = await _reserve();
    try {
      return await ref.read(storyApiProvider).generateStory(request);
    } catch (_) {
      try {
        await _refund(charge);
      } catch (_) {/* keep the original generation error */}
      rethrow;
    }
  }

  /// Reserves a free slot first, then a paid credit. Pro reserves nothing.
  Future<_Charge> _reserve() async {
    final entitlements = ref.read(entitlementsProvider).valueOrNull ?? const <String>{};
    if (entitlements.contains(AppConstants.proEntitlement)) return _Charge.pro;
    final count = ref.read(generatedCountProvider).valueOrNull ?? 0;
    if (count < AppConstants.freeStoryLimit) {
      await ref.read(generatedCountProvider.notifier).increment();
      return _Charge.free;
    }
    await ref.read(creditsProvider.notifier).consume();
    return _Charge.credit;
  }

  Future<void> _refund(_Charge charge) async {
    switch (charge) {
      case _Charge.pro:
        break;
      case _Charge.free:
        await ref.read(generatedCountProvider.notifier).decrement();
      case _Charge.credit:
        await ref.read(creditsProvider.notifier).add(1);
    }
  }
}

final storyControllerProvider =
    AsyncNotifierProvider<StoryController, Story?>(StoryController.new);
