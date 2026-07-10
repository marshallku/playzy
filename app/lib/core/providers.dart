import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/payment/fake_payment_gateway.dart';
import '../data/payment/payment_gateway.dart';
import '../data/profile/profile_repository.dart';
import '../data/story/fake_story_api.dart';
import '../data/story/story_api.dart';
import '../domain/child_profile.dart';
import '../domain/story.dart';
import 'constants.dart';

/// Composition root. Providers wire concrete implementations; tests override
/// them with fakes (ADR 0004). Swapping the AI backend or payment provider is a
/// one-line change here — no call-site edits.

/// Bound in main() after async init via ProviderScope overrides.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override sharedPreferencesProvider in main()'),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => PrefsProfileRepository(ref.watch(sharedPreferencesProvider)),
);

// M1 uses fakes; M2 swaps [storyApiProvider] to an HttpStoryApi (ADR 0001).
final storyApiProvider = Provider<StoryApi>((ref) => const FakeStoryApi());

final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  final gateway = FakePaymentGateway();
  ref.onDispose(gateway.dispose);
  return gateway;
});

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

/// Whether the user may generate another story: has Pro, is under the free
/// limit, or holds paid credits. **Fails closed while any input is still
/// loading** so the quota can't be bypassed during hydration (ADR 0002).
final canGenerateProvider = Provider<bool>((ref) {
  final countAsync = ref.watch(generatedCountProvider);
  final creditsAsync = ref.watch(creditsProvider);
  final entAsync = ref.watch(entitlementsProvider);
  // Fail closed unless every gate input has a real value — loading OR error
  // must never let a generation through (ADR 0002).
  if (!countAsync.hasValue || !creditsAsync.hasValue || !entAsync.hasValue) {
    return false;
  }
  final entitlements = entAsync.valueOrNull ?? const <String>{};
  if (entitlements.contains(AppConstants.proEntitlement)) return true;
  final count = countAsync.valueOrNull ?? 0;
  final credits = creditsAsync.valueOrNull ?? 0;
  return count < AppConstants.freeStoryLimit || credits > 0;
});

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
    // Reserve inside the try so a persistence failure still releases the lock.
    _Charge? charge;
    try {
      charge = await _reserve();
      final story = await ref.read(storyApiProvider).generateStory(request);
      state = AsyncData(story);
      return story;
    } catch (e, st) {
      // Best-effort rollback; a refund failure must not mask the original error.
      if (charge != null) {
        try {
          await _refund(charge);
        } catch (_) {/* keep the original generation error */}
      }
      state = AsyncError(e, st);
      rethrow;
    } finally {
      _inFlight = false;
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
