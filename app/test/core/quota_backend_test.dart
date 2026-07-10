import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/quota/quota_api.dart';
import 'package:playzy/data/story/fake_story_api.dart';
import 'package:playzy/data/story/story_api.dart';
import 'package:playzy/domain/quota_state.dart';
import 'package:playzy/domain/story.dart';

class _FailingStoryApi implements StoryApi {
  @override
  Future<Story> generateStory(StoryRequest request) async =>
      throw const StoryQuotaException();
}

/// Simulates backend mode: overriding [quotaApiProvider] with a non-null fake
/// flips the app onto the authoritative-quota path regardless of build config.
class _FakeQuotaApi implements QuotaApi {
  _FakeQuotaApi(this._state);
  QuotaState _state;
  int fetchCount = 0;
  int? lastGrant;

  @override
  Future<QuotaState> fetchQuota() async {
    fetchCount++;
    return _state;
  }

  @override
  Future<QuotaState> grantCreditsDev(int amount, String adminToken) async {
    lastGrant = amount;
    _state = QuotaState(
      freeUsed: _state.freeUsed,
      freeLimit: _state.freeLimit,
      credits: _state.credits + amount,
      canGenerate: true,
    );
    return _state;
  }
}

const _request = StoryRequest(childName: '하준', ageBand: 'toddler', situationIds: ['bedtime']);

ProviderContainer _backendContainer(_FakeQuotaApi api) {
  final c = ProviderContainer(overrides: [
    quotaApiProvider.overrideWithValue(api),
    storyApiProvider.overrideWithValue(const FakeStoryApi(delay: Duration.zero)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('backend-mode quota', () {
    test('quota + gating come from the backend api', () async {
      final api = _FakeQuotaApi(
        const QuotaState(freeUsed: 1, freeLimit: 3, credits: 0, canGenerate: true),
      );
      final c = _backendContainer(api);

      final q = await c.read(quotaStateProvider.future);
      expect(q.freeRemaining, 2);
      expect(c.read(canGenerateProvider), isTrue);
      expect(api.fetchCount, greaterThan(0));
    });

    test('fails closed when the backend says no', () async {
      final api = _FakeQuotaApi(
        const QuotaState(freeUsed: 3, freeLimit: 3, credits: 0, canGenerate: false),
      );
      final c = _backendContainer(api);
      await c.read(quotaStateProvider.future);
      expect(c.read(canGenerateProvider), isFalse);
    });

    test('generation refreshes the authoritative quota afterward', () async {
      final api = _FakeQuotaApi(
        const QuotaState(freeUsed: 0, freeLimit: 3, credits: 0, canGenerate: true),
      );
      final c = _backendContainer(api);
      await c.read(quotaStateProvider.future);
      final before = api.fetchCount;

      final story = await c.read(storyControllerProvider.notifier).generate(_request);
      expect(story.title, contains('하준'));

      // The backend charged server-side; the app re-fetches the fresh quota.
      await c.read(quotaStateProvider.future);
      expect(api.fetchCount, greaterThan(before));
    });

    test('a failed backend generation still refreshes the quota (no stale allowance)', () async {
      final api = _FakeQuotaApi(
        const QuotaState(freeUsed: 0, freeLimit: 3, credits: 0, canGenerate: true),
      );
      final c = ProviderContainer(overrides: [
        quotaApiProvider.overrideWithValue(api),
        storyApiProvider.overrideWithValue(_FailingStoryApi()),
      ]);
      addTearDown(c.dispose);
      await c.read(quotaStateProvider.future);
      final before = api.fetchCount;

      await expectLater(
        c.read(storyControllerProvider.notifier).generate(_request),
        throwsA(isA<StoryQuotaException>()),
      );

      await c.read(quotaStateProvider.future);
      expect(api.fetchCount, greaterThan(before));
    });
  });
}
