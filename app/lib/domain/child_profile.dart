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
    required this.givenName,
    this.familyName,
    required this.ageBand,
    this.interests = const [],
    this.companionName,
  });

  final String id;

  /// The child's given name (이름) — the ONLY name used in the story so a warm
  /// bedtime tale never addresses the child by surname.
  final String givenName;

  /// Optional family name (성). Collected but deliberately NOT used in the story.
  final String? familyName;

  final AgeBand ageBand;

  /// Favorite things (animals, vehicles, colors…) — chip-selected.
  final List<String> interests;

  /// Deprecated legacy default companion. No longer edited in the UI — retained
  /// only so the character roster can migrate it once (see [ProfileRepository]),
  /// which avoids dropping it before the roster has read it.
  final String? companionName;

  /// [clearCompanionName]/[clearFamilyName] clear the optional fields (passing
  /// `null` alone cannot distinguish "unset" from "clear").
  ChildProfile copyWith({
    String? givenName,
    String? familyName,
    AgeBand? ageBand,
    List<String>? interests,
    String? companionName,
    bool clearFamilyName = false,
    bool clearCompanionName = false,
  }) {
    return ChildProfile(
      id: id,
      givenName: givenName ?? this.givenName,
      familyName: clearFamilyName ? null : (familyName ?? this.familyName),
      ageBand: ageBand ?? this.ageBand,
      interests: interests ?? this.interests,
      companionName: clearCompanionName ? null : (companionName ?? this.companionName),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'givenName': givenName,
        if (familyName != null) 'familyName': familyName,
        'ageBand': ageBand.name,
        'interests': interests,
        // Kept (not dropped) so the roster migration can still read it (C2).
        if (companionName != null) 'companionName': companionName,
      };

  factory ChildProfile.fromJson(Map<String, dynamic> json) {
    // Migration: pre-split profiles stored a single `name`; treat it as the given
    // name verbatim (auto-splitting a surname is unreliable — e.g. "하준" is a
    // given name, not 하 + 준). The two-field editor lets the parent correct it.
    final given = (json['givenName'] as String?) ?? (json['name'] as String?) ?? '';
    return ChildProfile(
      id: json['id'] as String,
      givenName: given,
      familyName: json['familyName'] as String?,
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
      other.givenName == givenName &&
      other.familyName == familyName &&
      other.ageBand == ageBand &&
      other.companionName == companionName &&
      _listEq(other.interests, interests);

  @override
  int get hashCode =>
      Object.hash(id, givenName, familyName, ageBand, companionName, Object.hashAll(interests));
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
