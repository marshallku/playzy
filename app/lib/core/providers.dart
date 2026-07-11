import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog/catalog_api.dart';
import '../data/catalog/http_catalog_api.dart';
import '../data/library/story_library.dart';
import '../data/payment/fake_payment_gateway.dart';
import '../data/payment/payment_gateway.dart';
import '../data/profile/profile_repository.dart';
import '../data/quota/quota_api.dart';
import '../data/story/fake_story_api.dart';
import '../data/story/http_story_api.dart';
import '../data/story/story_api.dart';
import '../domain/child_profile.dart';
import '../domain/quota_state.dart';
import '../domain/story.dart';
import '../sdui/sdui_models.dart';
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
    ? HttpStoryApi(baseUrl: Env.apiBaseUrl, deviceId: ref.watch(deviceIdProvider))
    : const FakeStoryApi());

final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  final gateway = FakePaymentGateway();
  ref.onDispose(gateway.dispose);
  return gateway;
});

final catalogApiProvider = Provider<CatalogApi>((ref) =>
    Env.hasBackend ? HttpCatalogApi(baseUrl: Env.apiBaseUrl) : const FakeCatalogApi());

/// Backend quota client — non-null only in backend mode. When null, quota is
/// built from local mirrors (ADR 0002).
final quotaApiProvider = Provider<QuotaApi?>((ref) => Env.hasBackend
    ? HttpQuotaApi(baseUrl: Env.apiBaseUrl, deviceId: ref.watch(deviceIdProvider))
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

/// The child profile (null until set up). Loads on build; [save] persists.
class ProfileController extends AsyncNotifier<ChildProfile?> {
  @override
  Future<ChildProfile?> build() => ref.watch(profileRepositoryProvider).loadProfile();

  /// Persists the profile. Rethrows on failure so the caller can surface an
  /// error and NOT treat a failed save as success.
  Future<void> save(ChildProfile profile) async {
    state = const AsyncLoading();
    try {
      await ref.read(profileRepositoryProvider).saveProfile(profile);
      state = AsyncData(profile);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, ChildProfile?>(ProfileController.new);

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
    try {
      return await ref.read(storyApiProvider).generateStory(request);
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
