import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/domain/story.dart';

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
    test('serializes provider-agnostic fields; omits null companion', () {
      const req = StoryRequest(
        childName: '하준',
        ageBand: 'toddler',
        situationIds: ['bedtime', 'teeth'],
        interests: ['공룡'],
      );
      final json = req.toJson();
      expect(json['childName'], '하준');
      expect(json['situationIds'], ['bedtime', 'teeth']);
      expect(json.containsKey('companionName'), isFalse);
    });

    test('JSON round-trips', () {
      const req = StoryRequest(
        childName: '서연',
        ageBand: 'preschool',
        situationIds: ['dark'],
        interests: ['별', '달'],
        companionName: '아빠',
      );
      final decoded = StoryRequest.fromJson(req.toJson());
      expect(decoded.childName, '서연');
      expect(decoded.ageBand, 'preschool');
      expect(decoded.situationIds, ['dark']);
      expect(decoded.interests, ['별', '달']);
      expect(decoded.companionName, '아빠');
    });
  });
}
