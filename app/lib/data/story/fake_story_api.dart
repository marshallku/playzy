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
    final theme = request.situationIds.isEmpty ? '모험' : request.situationIds.first;
    final companion = request.companionName;

    return Story(
      id: 'fake-${request.situationIds.join("-")}-${name.hashCode}',
      title: '$name의 $theme 이야기',
      pages: [
        StoryPage(text: '옛날 옛적, $name(이)가 살고 있었어요.'),
        if (companion != null) StoryPage(text: '$name는 $companion와(과) 함께 길을 나섰어요.'),
        StoryPage(text: '오늘은 특별한 하루였어요. $name는 용기를 냈답니다.'),
        StoryPage(text: '그렇게 $name는 포근하게 잠이 들었어요. 잘 자요, $name.'),
      ],
    );
  }
}
