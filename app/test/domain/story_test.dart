import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/domain/story.dart';
import 'package:playzy/domain/story_options.dart';

void main() {
  group('Story', () {
    const story = Story(
      id: 's1',
      title: '하준이의 양치 모험',
      pages: [
        StoryPage(text: '옛날 옛적에...'),
        StoryPage(text: '하준이는 칫솔을 들었어요.'),
      ],
      createdAtIso: '2026-07-11T12:00:00Z',
    );

    test('JSON round-trips with pages', () {
      final decoded = Story.fromJson(story.toJson());
      expect(decoded.id, 's1');
      expect(decoded.title, story.title);
      expect(decoded.pages.length, 2);
      expect(decoded.pages.first.text, '옛날 옛적에...');
      expect(decoded.createdAtIso, '2026-07-11T12:00:00Z');
    });

    test('text-only page omits imageUrl (D3 MVP)', () {
      final json = const StoryPage(text: 'hi').toJson();
      expect(json.containsKey('imageUrl'), isFalse);
    });

    test('page preserves imageUrl when present (illustration fast-follow)', () {
      final decoded = StoryPage.fromJson({'text': 't', 'imageUrl': 'https://x/y.png'});
      expect(decoded.imageUrl, 'https://x/y.png');
    });
  });

  group('StoryRequest', () {
    test('serializes provider-agnostic fields', () {
      const req = StoryRequest(
        childName: '하준',
        ageBand: 'toddler',
        situationIds: ['bedtime', 'teeth'],
        interests: ['공룡'],
      );
      final json = req.toJson();
      expect(json['childName'], '하준');
      expect(json['situationIds'], ['bedtime', 'teeth']);
      expect(json['interests'], ['공룡']);
    });

    test('JSON round-trips', () {
      const req = StoryRequest(
        childName: '서연',
        ageBand: 'preschool',
        situationIds: ['dark'],
        interests: ['별', '달'],
      );
      final decoded = StoryRequest.fromJson(req.toJson());
      expect(decoded.childName, '서연');
      expect(decoded.ageBand, 'preschool');
      expect(decoded.situationIds, ['dark']);
      expect(decoded.interests, ['별', '달']);
    });

    test('defaults: cozy mood, no explicit length/characters', () {
      const req = StoryRequest(childName: '하준', ageBand: 'toddler', situationIds: ['bedtime']);
      expect(req.mood, StoryMood.cozy);
      expect(req.length, isNull); // null = age-band default (C2 backward compat)
      expect(req.characters, isEmpty);
      final json = req.toJson();
      expect(json['mood'], 'cozy');
      // length omitted when unset so the backend keeps the age-appropriate count.
      expect(json.containsKey('length'), isFalse);
    });

    test('round-trips characters, mood, length (planning/40)', () {
      const req = StoryRequest(
        childName: '하준',
        ageBand: 'toddler',
        situationIds: ['bedtime'],
        characters: [
          StoryCharacter(name: '하율', kind: CharacterKind.family),
          StoryCharacter(name: '뽀삐', kind: CharacterKind.animal),
        ],
        mood: StoryMood.adventurous,
        length: StoryLength.long,
      );
      final decoded = StoryRequest.fromJson(req.toJson());
      expect(decoded.characters, req.characters);
      expect(decoded.mood, StoryMood.adventurous);
      expect(decoded.length, StoryLength.long);
    });

    test('serializes topic when present; omits when null/blank', () {
      const withTopic = StoryRequest(
        childName: '하준',
        ageBand: 'toddler',
        situationIds: [],
        topic: '오늘 이가 났어요',
      );
      expect(withTopic.toJson()['topic'], '오늘 이가 났어요');
      expect(StoryRequest.fromJson(withTopic.toJson()).topic, '오늘 이가 났어요');

      const blankTopic = StoryRequest(
        childName: '하준',
        ageBand: 'toddler',
        situationIds: ['bedtime'],
        topic: '   ',
      );
      expect(blankTopic.toJson().containsKey('topic'), isFalse);
    });

    test('tolerates missing situationIds (topic-only request)', () {
      final decoded = StoryRequest.fromJson({
        'childName': '하준',
        'ageBand': 'toddler',
        'topic': '오늘 이야기',
      });
      expect(decoded.situationIds, isEmpty);
      expect(decoded.topic, '오늘 이야기');
    });

    test('tolerates unknown enum names → falls back rather than throwing', () {
      final decoded = StoryRequest.fromJson({
        'childName': '하준',
        'ageBand': 'toddler',
        'situationIds': ['bedtime'],
        'mood': 'nonsense',
        'length': 'huge',
        'characters': [
          {'name': '지우', 'kind': 'hacker'},
        ],
      });
      expect(decoded.mood, StoryMood.cozy);
      expect(decoded.length, isNull); // unknown length → null (age default)
      expect(decoded.characters.single.kind, CharacterKind.friend);
    });
  });
}
