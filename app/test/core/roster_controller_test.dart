import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/constants.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/domain/story_options.dart';

void main() {
  ProviderContainer containerWith(FakeProfileRepository repo) {
    final c = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('RosterController', () {
    test('add persists and dedupes by (name, kind)', () async {
      final repo = FakeProfileRepository(roster: const []);
      final c = containerWith(repo);
      final ctrl = c.read(rosterControllerProvider.notifier);
      await c.read(rosterControllerProvider.future);

      await ctrl.add(const StoryCharacter(name: '뽀삐', kind: CharacterKind.animal));
      await ctrl.add(const StoryCharacter(name: '  뽀삐 ', kind: CharacterKind.animal)); // dup (trimmed)
      await ctrl.add(const StoryCharacter(name: '뽀삐', kind: CharacterKind.friend)); // diff kind → kept

      final roster = c.read(rosterControllerProvider).valueOrNull!;
      expect(roster.length, 2);
      expect(await repo.loadRoster(), roster); // persisted
    });

    test('a blank name is ignored', () async {
      final c = containerWith(FakeProfileRepository(roster: const []));
      final ctrl = c.read(rosterControllerProvider.notifier);
      await c.read(rosterControllerProvider.future);
      await ctrl.add(const StoryCharacter(name: '   ', kind: CharacterKind.family));
      expect(c.read(rosterControllerProvider).valueOrNull, isEmpty);
    });

    test('the roster is capped at maxRosterCharacters', () async {
      final c = containerWith(FakeProfileRepository(roster: const []));
      final ctrl = c.read(rosterControllerProvider.notifier);
      await c.read(rosterControllerProvider.future);
      for (var i = 0; i < AppConstants.maxRosterCharacters + 3; i++) {
        await ctrl.add(StoryCharacter(name: '인물$i', kind: CharacterKind.friend));
      }
      expect(c.read(rosterControllerProvider).valueOrNull!.length,
          AppConstants.maxRosterCharacters);
    });

    test('remove drops the matching character and persists', () async {
      final repo = FakeProfileRepository(roster: const [
        StoryCharacter(name: '뽀삐', kind: CharacterKind.animal),
        StoryCharacter(name: '이모', kind: CharacterKind.family),
      ]);
      final c = containerWith(repo);
      final ctrl = c.read(rosterControllerProvider.notifier);
      await c.read(rosterControllerProvider.future);

      await ctrl.remove(const StoryCharacter(name: '뽀삐', kind: CharacterKind.animal));
      final roster = c.read(rosterControllerProvider).valueOrNull!;
      expect(roster.map((e) => e.name), ['이모']);
      expect(await repo.loadRoster(), roster);
    });
  });
}
