// Generation-time story controls (docs/planning/40). These ride along with the
// StoryRequest; the backend owns how they shape the prompt (ADR 0001).

/// A named character to feature beyond the main child (등장인물). Distinct from
/// the profile's single [ChildProfile.companionName] default.
enum CharacterKind {
  family, // 가족
  friend, // 친구
  animal, // 동물
  imaginary; // 상상 친구

  String get label => switch (this) {
        CharacterKind.family => '가족',
        CharacterKind.friend => '친구',
        CharacterKind.animal => '동물',
        CharacterKind.imaginary => '상상 친구',
      };
}

class StoryCharacter {
  const StoryCharacter({required this.name, required this.kind});

  final String name;
  final CharacterKind kind;

  Map<String, dynamic> toJson() => {'name': name, 'kind': kind.name};

  factory StoryCharacter.fromJson(Map<String, dynamic> json) => StoryCharacter(
        name: json['name'] as String,
        // Tolerant: an unknown kind falls back to friend rather than throwing.
        kind: enumByName(CharacterKind.values, json['kind'] as String?, CharacterKind.friend),
      );

  @override
  bool operator ==(Object other) =>
      other is StoryCharacter && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(name, kind);
}

/// Tone of the story (분위기). Bedtime default is [cozy].
enum StoryMood {
  cozy,
  cheerful,
  adventurous,
  calm,
  playful;

  String get label => switch (this) {
        StoryMood.cozy => '포근한',
        StoryMood.cheerful => '신나는',
        StoryMood.adventurous => '모험적인',
        StoryMood.calm => '잔잔한',
        StoryMood.playful => '유쾌한',
      };
}

/// Length of the story (길이) → target page count on the backend. Omitting it
/// keeps the age-band default; only an explicit length overrides (planning/40).
enum StoryLength {
  short,
  medium,
  long;

  String get label => switch (this) {
        StoryLength.short => '짧게',
        StoryLength.medium => '보통',
        StoryLength.long => '길게',
      };
}

/// Case-tolerant enum lookup by [Enum.name] — an unknown/legacy name yields the
/// fallback rather than throwing, so old persisted or malformed data still loads.
T enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Like [enumByName] but returns null for an absent/unknown name (for optionals).
T? enumByNameOrNull<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
