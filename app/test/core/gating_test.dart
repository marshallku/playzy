import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/constants.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/payment/fake_payment_gateway.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/data/story/story_api.dart';
import 'package:playzy/domain/story.dart';

/// A StoryApi that always fails — to exercise the reserve/refund rollback.
class _FailingStoryApi implements StoryApi {
  @override
  Future<Story> generateStory(StoryRequest request) async =>
      throw const StoryApiException('boom');
}

/// Reservation (quota persistence) always fails — to prove the in-flight lock
/// is released even when _reserve throws.
class _ReserveFailingRepo extends FakeProfileRepository {
  @override
  Future<void> incrementGeneratedCount() async => throw Exception('disk full');
}

/// Reading the quota count fails — to prove gating fails closed on error.
class _CountFailingRepo extends FakeProfileRepository {
  @override
  Future<int> generatedCount() async => throw Exception('read error');
}

ProviderContainer _container({
  required int count,
  int credits = 0,
  Set<String> entitlements = const {},
}) {
  final container = ProviderContainer(
    overrides: [
      profileRepositoryProvider
          .overrideWithValue(FakeProfileRepository(count: count, credits: credits)),
      paymentGatewayProvider
          .overrideWithValue(FakePaymentGateway(initialEntitlements: entitlements)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _warmUp(ProviderContainer c) async {
  await c.read(generatedCountProvider.future);
  await c.read(creditsProvider.future);
  await c.read(entitlementsProvider.future);
}

const _request = StoryRequest(
  childName: '하준',
  ageBand: 'toddler',
  situationIds: ['bedtime'],
);

void main() {
  group('canGenerateProvider (free-tier gating)', () {
    test('fails closed while inputs are still loading', () {
      final c = _container(count: 0);
      // No warm-up: async providers are loading → must not allow generation.
      expect(c.read(canGenerateProvider), isFalse);
    });

    test('fails closed when a quota input errors (not just loading)', () async {
      final c = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(_CountFailingRepo()),
          paymentGatewayProvider.overrideWithValue(FakePaymentGateway()),
        ],
      );
      addTearDown(c.dispose);

      await expectLater(c.read(generatedCountProvider.future), throwsA(anything));
      await c.read(creditsProvider.future);
      await c.read(entitlementsProvider.future);

      expect(c.read(canGenerateProvider), isFalse);
    });

    test('allows generation under the free limit', () async {
      final c = _container(count: AppConstants.freeStoryLimit - 1);
      await _warmUp(c);
      expect(c.read(canGenerateProvider), isTrue);
    });

    test('blocks generation at the free limit without Pro or credits', () async {
      final c = _container(count: AppConstants.freeStoryLimit);
      await _warmUp(c);
      expect(c.read(canGenerateProvider), isFalse);
    });

    test('paid credits allow generation past the free limit', () async {
      final c = _container(count: AppConstants.freeStoryLimit, credits: 2);
      await _warmUp(c);
      expect(c.read(canGenerateProvider), isTrue);
    });

    test('Pro entitlement lifts the limit', () async {
      final c = _container(
        count: AppConstants.freeStoryLimit + 5,
        entitlements: {AppConstants.proEntitlement},
      );
      await _warmUp(c);
      expect(c.read(canGenerateProvider), isTrue);
    });
  });

  group('StoryController.generate (quota enforcement)', () {
    test('produces a story and consumes a free slot under the limit', () async {
      final c = _container(count: 0);
      await _warmUp(c);

      final story = await c.read(storyControllerProvider.notifier).generate(_request);

      expect(story.title, contains('하준'));
      expect(await c.read(generatedCountProvider.future), 1);
    });

    test('throws QuotaExceededException at the limit with no credits', () async {
      final c = _container(count: AppConstants.freeStoryLimit);
      await _warmUp(c);

      expect(
        () => c.read(storyControllerProvider.notifier).generate(_request),
        throwsA(isA<QuotaExceededException>()),
      );
    });

    test('consumes a paid credit when the free limit is exhausted', () async {
      final c = _container(count: AppConstants.freeStoryLimit, credits: 2);
      await _warmUp(c);

      await c.read(storyControllerProvider.notifier).generate(_request);

      expect(await c.read(creditsProvider.future), 1);
      // Free count is untouched once we're on credits.
      expect(await c.read(generatedCountProvider.future), AppConstants.freeStoryLimit);
    });

    test('refunds the reserved quota when generation fails', () async {
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository(count: 0)),
          paymentGatewayProvider.overrideWithValue(FakePaymentGateway()),
          storyApiProvider.overrideWithValue(_FailingStoryApi()),
        ],
      );
      addTearDown(container.dispose);
      await _warmUp(container);

      await expectLater(
        container.read(storyControllerProvider.notifier).generate(_request),
        throwsA(isA<StoryApiException>()),
      );

      // Reservation rolled back — a failed generation is not charged.
      expect(await container.read(generatedCountProvider.future), 0);
    });

    test('a reservation failure releases the in-flight lock', () async {
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(_ReserveFailingRepo()),
          paymentGatewayProvider.overrideWithValue(FakePaymentGateway()),
        ],
      );
      addTearDown(container.dispose);
      await _warmUp(container);
      final notifier = container.read(storyControllerProvider.notifier);

      // First attempt fails inside reserve...
      await expectLater(
        notifier.generate(_request),
        throwsA(isNot(isA<QuotaExceededException>())),
      );
      // ...and the lock is released, so a retry reaches the repo again rather
      // than being rejected as "already in flight".
      await expectLater(
        notifier.generate(_request),
        throwsA(isNot(isA<QuotaExceededException>())),
      );
    });

    test('serializes concurrent generations to protect the quota', () async {
      final c = _container(count: 0);
      await _warmUp(c);
      final notifier = c.read(storyControllerProvider.notifier);

      final first = notifier.generate(_request);
      // A second call while the first is in flight is rejected, not run.
      await expectLater(
        notifier.generate(_request),
        throwsA(isA<QuotaExceededException>()),
      );
      await first;

      expect(await c.read(generatedCountProvider.future), 1);
    });

    test('Pro generates without consuming free slots or credits', () async {
      final c = _container(
        count: AppConstants.freeStoryLimit,
        credits: 2,
        entitlements: {AppConstants.proEntitlement},
      );
      await _warmUp(c);

      await c.read(storyControllerProvider.notifier).generate(_request);

      expect(await c.read(generatedCountProvider.future), AppConstants.freeStoryLimit);
      expect(await c.read(creditsProvider.future), 2);
    });
  });
}
