import '../../domain/story.dart';
import 'story_api.dart';

/// Offline/dev implementation of [StoryApi]. Fabricates a warm, deterministic
/// story from the request so the whole UI can be built and tested before the
/// backend exists (ADR 0001 app-side seam). Deterministic by design — no
/// randomness — so widget tests are stable.
class FakeStoryApi implements StoryApi {
  const FakeStoryApi({this.delay = const Duration(milliseconds: 400)});

  /// Simulates generation latency so the loading state is exercised.
  final Duration delay;

  @override
  Future<Story> generateStory(StoryRequest request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final name = request.childName.trim().isEmpty ? '아이' : request.childName.trim();
    final topic = request.topic?.trim();
    // The free-text seed is the story's subject when given; else a picked
    // situation; else a generic adventure.
    final theme = (topic != null && topic.isNotEmpty)
        ? topic
        : (request.situationIds.isEmpty ? '모험' : request.situationIds.first);
    final companion = request.companionName;
    final mood = request.mood.label; // 포근한, 신나는, …

    // Id folds in EVERY option (topic/mood/length/characters incl. kind) so any
    // varied choice yields a distinct story, while an identical request stays
    // stable for deterministic tests (planning/40, C2).
    final optionKey = [
      topic ?? '',
      request.mood.name,
      request.length?.name ?? 'age',
      request.characters.map((c) => '${c.name}:${c.kind.name}').join(','),
    ].join('-');

    return Story(
      id: 'fake-${request.situationIds.join("-")}-$optionKey-${name.hashCode}',
      title: '$name의 $theme 이야기',
      pages: [
        StoryPage(text: '$mood 밤이에요. 옛날 옛적, $name(이)가 살고 있었어요.'),
        if (topic != null && topic.isNotEmpty)
          StoryPage(text: '오늘은 "$topic" 이야기를 들려줄게요.'),
        if (companion != null) StoryPage(text: '$name는 $companion와(과) 함께 길을 나섰어요.'),
        // Reflect the chosen characters so the demo isn't flat (planning/40).
        for (final c in request.characters)
          StoryPage(text: '${c.name}(${c.kind.label})도 함께라서 더 즐거웠어요.'),
        // Mood is reflected here so changing mood ALONE changes visible content.
        StoryPage(text: '$mood 하루였어요. $name는 용기를 냈답니다.'),
        StoryPage(text: '그렇게 $name는 포근하게 잠이 들었어요. 잘 자요, $name.'),
      ],
    );
  }
}
