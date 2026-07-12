import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/domain/child_profile.dart';
import 'package:playzy/domain/story_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PrefsProfileRepository> repoWith(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    return PrefsProfileRepository(await SharedPreferences.getInstance());
  }

  group('PrefsProfileRepository roster', () {
    test('seeds the roster once from the legacy profile companion (C2)', () async {
      final profileJson = jsonEncode(const ChildProfile(
        id: 'c1',
        givenName: '하준',
        ageBand: AgeBand.toddler,
        companionName: '누나',
      ).toJson());
      final repo = await repoWith({'child_profile': profileJson});

      final seeded = await repo.loadRoster();
      expect(seeded.length, 1);
      expect(seeded.single.name, '누나');
      expect(seeded.single.kind, CharacterKind.friend);
    });

    test('an emptied roster is NOT re-seeded from the companion', () async {
      final profileJson = jsonEncode(const ChildProfile(
        id: 'c1',
        givenName: '하준',
        ageBand: AgeBand.toddler,
        companionName: '누나',
      ).toJson());
      final repo = await repoWith({'child_profile': profileJson});

      await repo.loadRoster(); // seeds + persists
      await repo.saveRoster(const []); // user clears it
      expect(await repo.loadRoster(), isEmpty); // stays empty
    });

    test('no companion → empty roster, not an error', () async {
      final repo = await repoWith({});
      expect(await repo.loadRoster(), isEmpty);
    });

    test('an empty migration persists the marker — a later companion does not re-seed (C2)', () async {
      final repo = await repoWith({}); // no profile/companion → migrates empty
      expect(await repo.loadRoster(), isEmpty);
      // A profile with a companion appearing AFTER migration must not re-seed.
      await repo.saveProfile(const ChildProfile(
        id: 'c1',
        givenName: '하준',
        ageBand: AgeBand.toddler,
        companionName: '누나',
      ));
      expect(await repo.loadRoster(), isEmpty);
    });

    test('saved roster round-trips', () async {
      final repo = await repoWith({});
      const roster = [
        StoryCharacter(name: '뽀삐', kind: CharacterKind.animal),
        StoryCharacter(name: '이모', kind: CharacterKind.family),
      ];
      await repo.saveRoster(roster);
      expect(await repo.loadRoster(), roster);
    });

    test('a corrupt entry is skipped, not fatal to the whole load (C5)', () async {
      final raw = jsonEncode([
        {'name': '뽀삐', 'kind': 'animal'},
        {'oops': true}, // no name → skipped
        'not-an-object', // skipped
        {'name': '이모', 'kind': 'family'},
      ]);
      final repo = await repoWith({'character_roster': raw});
      final loaded = await repo.loadRoster();
      expect(loaded.map((c) => c.name), ['뽀삐', '이모']);
    });
  });
}
