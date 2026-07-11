import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/library/story_library.dart';
import 'package:playzy/data/payment/fake_payment_gateway.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/domain/story.dart';

/// A library whose save always fails — to prove a save failure never fails
/// generation or re-charges quota (C3).
class _ThrowingLibrary implements StoryLibrary {
  @override
  Future<List<Story>> recent() async => const [];
  @override
  Future<void> save(Story story) async => throw Exception('disk full');
}

const _request = StoryRequest(
  childName: '하준',
  ageBand: 'toddler',
  situationIds: ['bedtime'],
);

ProviderContainer _container(StoryLibrary library) {
  final container = ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(FakeProfileRepository(count: 0)),
      paymentGatewayProvider.overrideWithValue(FakePaymentGateway()),
      storyLibraryProvider.overrideWithValue(library),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _warmUp(ProviderContainer c) async {
  await c.read(generatedCountProvider.future);
  await c.read(creditsProvider.future);
  await c.read(entitlementsProvider.future);
  await c.read(quotaStateProvider.future);
}

void main() {
  test('a successful generation is saved to the library', () async {
    final library = FakeStoryLibrary();
    final container = _container(library);
    await _warmUp(container);

    final story =
        await container.read(storyControllerProvider.notifier).generate(_request);

    expect((await library.recent()).map((s) => s.id), contains(story.id));
  });

  test('a library-save failure does not fail generation', () async {
    final container = _container(_ThrowingLibrary());
    await _warmUp(container);

    // Must not throw — the story is returned even though persistence failed.
    final story =
        await container.read(storyControllerProvider.notifier).generate(_request);
    expect(story.pages, isNotEmpty);

    // And the free slot was still consumed exactly once (not rolled back).
    expect(await container.read(generatedCountProvider.future), 1);
  });
}
