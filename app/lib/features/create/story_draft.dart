import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/story_options.dart';

/// The in-progress story the parent is building across the 3 funnel steps
/// (topic → cast → tone). Held in a provider — NOT passed via route `extra` —
/// so going back (native swipe/back) rehydrates each step and choices survive
/// (Q3). Reset once at the fresh entry point (Home CTA), never mid-funnel, so a
/// failed generation keeps the choices for another try.
class StoryDraft {
  const StoryDraft({
    this.topic = '',
    this.situationIds = const {},
    this.cast = const [],
    this.mood = StoryMood.cozy,
    this.length,
  });

  final String topic;
  final Set<String> situationIds;
  final List<StoryCharacter> cast;
  final StoryMood mood;
  final StoryLength? length;

  /// The story needs SOMETHING to be about: a typed seed or at least one
  /// situation chip. Mirrors the backend's validation (topic OR situationId).
  bool get hasSubject => topic.trim().isNotEmpty || situationIds.isNotEmpty;

  /// Whether [character] is currently selected for tonight's story.
  bool isCast(StoryCharacter character) =>
      cast.any((c) => c.name == character.name && c.kind == character.kind);

  StoryDraft copyWith({
    String? topic,
    Set<String>? situationIds,
    List<StoryCharacter>? cast,
    StoryMood? mood,
    StoryLength? length,
    bool clearLength = false,
  }) {
    return StoryDraft(
      topic: topic ?? this.topic,
      situationIds: situationIds ?? this.situationIds,
      cast: cast ?? this.cast,
      mood: mood ?? this.mood,
      length: clearLength ? null : (length ?? this.length),
    );
  }
}

class StoryDraftNotifier extends Notifier<StoryDraft> {
  @override
  StoryDraft build() => const StoryDraft();

  void setTopic(String topic) => state = state.copyWith(topic: topic);

  void toggleSituation(String id, {int? max}) {
    final next = Set<String>.of(state.situationIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      if (max != null && next.length >= max) return;
      next.add(id);
    }
    state = state.copyWith(situationIds: next);
  }

  /// Toggles a cast member on/off. When adding, [max] caps how many can ride
  /// along in one story (mirrors the backend character cap).
  void toggleCast(StoryCharacter character, {int? max}) {
    final present = state.cast.any((c) => _same(c, character));
    if (present) {
      state = state.copyWith(
        cast: state.cast.where((c) => !_same(c, character)).toList(),
      );
    } else {
      if (max != null && state.cast.length >= max) return;
      state = state.copyWith(cast: [...state.cast, character]);
    }
  }

  void setMood(StoryMood mood) => state = state.copyWith(mood: mood);

  /// Re-selecting the current length clears it → age-band default.
  void setLength(StoryLength? length) => state = state.copyWith(
        length: length,
        clearLength: length == null || length == state.length,
      );

  void reset() => state = const StoryDraft();

  bool _same(StoryCharacter a, StoryCharacter b) =>
      a.name == b.name && a.kind == b.kind;
}

final storyDraftProvider =
    NotifierProvider<StoryDraftNotifier, StoryDraft>(StoryDraftNotifier.new);
