import 'story_options.dart';

/// A generated story, structured as title + pages so the reader can paginate
/// (docs/planning/10). Text-only for MVP (D3); [imageUrl] is reserved for the
/// illustration fast-follow.
class Story {
  const Story({
    required this.id,
    required this.title,
    required this.pages,
    this.createdAtIso,
  });

  final String id;
  final String title;
  final List<StoryPage> pages;

  /// ISO-8601 creation timestamp (set by the backend/caller, not the model).
  final String? createdAtIso;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'pages': pages.map((p) => p.toJson()).toList(),
        if (createdAtIso != null) 'createdAt': createdAtIso,
      };

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'] as String,
      title: json['title'] as String,
      pages: (json['pages'] as List<dynamic>)
          .map((e) => StoryPage.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAtIso: json['createdAt'] as String?,
    );
  }

  @override
  bool operator ==(Object other) => other is Story && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class StoryPage {
  const StoryPage({required this.text, this.imageUrl});

  final String text;

  /// Reserved for AI illustration (D3) — null in the text-only MVP.
  final String? imageUrl;

  Map<String, dynamic> toJson() => {
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };

  factory StoryPage.fromJson(Map<String, dynamic> json) {
    return StoryPage(
      text: json['text'] as String,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

/// The provider-agnostic request the app sends to the Playzy story API
/// (ADR 0001). The backend turns this into a prompt; the app never builds one.
/// The generation controls ([characters]/[mood]/[length]/[setting], planning/40)
/// are additive with safe defaults so older callers keep working.
class StoryRequest {
  const StoryRequest({
    required this.childName,
    required this.ageBand,
    required this.situationIds,
    this.interests = const [],
    this.companionName,
    this.characters = const [],
    this.mood = StoryMood.cozy,
    this.length,
    this.setting,
  });

  final String childName;
  final String ageBand;
  final List<String> situationIds;
  final List<String> interests;
  final String? companionName;

  /// Extra named characters to feature (등장인물).
  final List<StoryCharacter> characters;
  final StoryMood mood;

  /// Explicit length override; **null = use the age-band default** (planning/40,
  /// C2). Omitted from the wire when null so the backend keeps age-appropriate
  /// length for callers that don't choose one.
  final StoryLength? length;

  /// Optional backdrop; null lets the backend/AI choose (planning/40).
  final StorySetting? setting;

  Map<String, dynamic> toJson() => {
        'childName': childName,
        'ageBand': ageBand,
        'situationIds': situationIds,
        'interests': interests,
        if (companionName != null) 'companionName': companionName,
        'characters': characters.map((c) => c.toJson()).toList(),
        'mood': mood.name,
        if (length != null) 'length': length!.name,
        if (setting != null) 'setting': setting!.name,
      };

  factory StoryRequest.fromJson(Map<String, dynamic> json) {
    return StoryRequest(
      childName: json['childName'] as String,
      ageBand: json['ageBand'] as String,
      situationIds:
          (json['situationIds'] as List<dynamic>).map((e) => e as String).toList(),
      interests: (json['interests'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      companionName: json['companionName'] as String?,
      characters: (json['characters'] as List<dynamic>? ?? const [])
          .map((e) => StoryCharacter.fromJson(e as Map<String, dynamic>))
          .toList(),
      mood: enumByName(StoryMood.values, json['mood'] as String?, StoryMood.cozy),
      length: enumByNameOrNull(StoryLength.values, json['length'] as String?),
      setting: enumByNameOrNull(StorySetting.values, json['setting'] as String?),
    );
  }
}
