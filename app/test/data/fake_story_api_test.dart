import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/data/story/fake_story_api.dart';
import 'package:playzy/data/story/story_api.dart';
import 'package:playzy/domain/story.dart';
import 'package:playzy/domain/story_options.dart';

void main() {
  group('FakeStoryApi', () {
    const api = FakeStoryApi(delay: Duration.zero);

    test('implements the StoryApi seam', () {
      expect(api, isA<StoryApi>());
    });

    test('produces a titled, multi-page story featuring the child name', () async {
      final story = await api.generateStory(const StoryRequest(
        childName: '하준',
        ageBand: 'toddler',
        situationIds: ['bedtime'],
      ));
      expect(story.title, contains('하준'));
      expect(story.pages.length, greaterThanOrEqualTo(3));
      expect(story.pages.every((p) => p.text.isNotEmpty), isTrue);
    });

    test('is deterministic for the same request (stable tests)', () async {
      const req = StoryRequest(childName: '서연', ageBand: 'infant', situationIds: ['teeth']);
      final a = await api.generateStory(req);
      final b = await api.generateStory(req);
      expect(a.id, b.id);
      expect(a.title, b.title);
    });

    test('reflects requested characters in the pages (planning/40)', () async {
      final story = await api.generateStory(const StoryRequest(
        childName: '하준',
        ageBand: 'toddler',
        situationIds: ['forest'],
        characters: [StoryCharacter(name: '뽀삐', kind: CharacterKind.animal)],
      ));
      expect(story.pages.any((p) => p.text.contains('뽀삐')), isTrue);
    });

    test('different options yield a distinct story id (varied, not same-y)', () async {
      const base = StoryRequest(childName: '하준', ageBand: 'toddler', situationIds: ['bedtime']);
      final cozy = await api.generateStory(base);
      final adventurous = await api.generateStory(const StoryRequest(
        childName: '하준',
        ageBand: 'toddler',
        situationIds: ['bedtime'],
        mood: StoryMood.adventurous,
      ));
      expect(cozy.id, isNot(adventurous.id));
    });
  });
}
