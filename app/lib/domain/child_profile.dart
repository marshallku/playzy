import 'dart:convert';

/// Coarse age bands drive vocabulary, length, and tone (docs/planning/10).
enum AgeBand {
  infant, // 0-1
  toddler, // 2-3
  preschool, // 4-5
  kindergarten; // 6

  String get label => switch (this) {
        AgeBand.infant => '0–1세',
        AgeBand.toddler => '2–3세',
        AgeBand.preschool => '4–5세',
        AgeBand.kindergarten => '6세',
      };
}

/// A child the parent generates stories for. Set up once, remembered.
/// Pure data — no Flutter, no IO. Persisted locally + sent to the story API.
class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    required this.ageBand,
    this.interests = const [],
    this.companionName,
  });

  final String id;
  final String name;
  final AgeBand ageBand;

  /// Favorite things (animals, vehicles, colors…) — chip-selected.
  final List<String> interests;

  /// Optional sibling/companion name to feature.
  final String? companionName;

  /// [clearCompanionName] clears the optional companion (passing
  /// `companionName: null` alone cannot distinguish "unset" from "clear").
  ChildProfile copyWith({
    String? name,
    AgeBand? ageBand,
    List<String>? interests,
    String? companionName,
    bool clearCompanionName = false,
  }) {
    return ChildProfile(
      id: id,
      name: name ?? this.name,
      ageBand: ageBand ?? this.ageBand,
      interests: interests ?? this.interests,
      companionName: clearCompanionName ? null : (companionName ?? this.companionName),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ageBand': ageBand.name,
        'interests': interests,
        if (companionName != null) 'companionName': companionName,
      };

  factory ChildProfile.fromJson(Map<String, dynamic> json) {
    return ChildProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      ageBand: AgeBand.values.byName(json['ageBand'] as String),
      interests: (json['interests'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      companionName: json['companionName'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());
  static ChildProfile decode(String raw) =>
      ChildProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      other is ChildProfile &&
      other.id == id &&
      other.name == name &&
      other.ageBand == ageBand &&
      other.companionName == companionName &&
      _listEq(other.interests, interests);

  @override
  int get hashCode => Object.hash(id, name, ageBand, companionName, Object.hashAll(interests));
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
