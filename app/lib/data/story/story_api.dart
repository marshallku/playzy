import '../../domain/story.dart';

/// The stable, provider-agnostic story API the app depends on (ADR 0001).
/// The app never talks to an AI provider directly — an implementation of this
/// interface (HTTP → Playzy backend, or a fake) is injected at the root.
abstract interface class StoryApi {
  /// Generate a story for the given request. Throws [StoryApiException] on
  /// failure; callers map that to UI state.
  Future<Story> generateStory(StoryRequest request);
}

class StoryApiException implements Exception {
  const StoryApiException(this.message);
  final String message;
  @override
  String toString() => 'StoryApiException: $message';
}

/// The backend refused generation because the quota is used up (HTTP 402).
/// The UI routes this to the paywall rather than showing a generic error.
class StoryQuotaException extends StoryApiException {
  const StoryQuotaException() : super('quota exceeded');
}
