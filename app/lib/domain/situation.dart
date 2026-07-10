/// Two families of situations (docs/planning/10). The parenting family is the
/// product's wedge; the theme family is the adventure/whimsy set.
enum SituationKind { parenting, theme }

/// A tappable situation/theme the parent picks for tonight's story.
/// The catalog is served by the backend (SDUI — ADR 0003) so it can grow
/// without an app release; a bundled default set backs offline use.
class Situation {
  const Situation({
    required this.id,
    required this.label,
    required this.kind,
    this.emoji,
  });

  final String id;
  final String label;
  final SituationKind kind;
  final String? emoji;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        if (emoji != null) 'emoji': emoji,
      };

  factory Situation.fromJson(Map<String, dynamic> json) {
    return Situation(
      id: json['id'] as String,
      label: json['label'] as String,
      kind: SituationKind.values.byName(json['kind'] as String),
      emoji: json['emoji'] as String?,
    );
  }

  @override
  bool operator ==(Object other) => other is Situation && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Bundled default catalog — the offline fallback when the SDUI catalog can't
/// load, so a parent is never stuck (ADR 0003). The wedge situations come first.
const List<Situation> kDefaultSituations = [
  // Parenting situations (the wedge)
  Situation(id: 'bedtime', label: '잠자기', kind: SituationKind.parenting, emoji: '🌙'),
  Situation(id: 'teeth', label: '양치하기', kind: SituationKind.parenting, emoji: '🪥'),
  Situation(id: 'potty', label: '배변 훈련', kind: SituationKind.parenting, emoji: '🚽'),
  Situation(id: 'sharing', label: '나눠 쓰기', kind: SituationKind.parenting, emoji: '🤝'),
  Situation(id: 'daycare', label: '어린이집 가기', kind: SituationKind.parenting, emoji: '🎒'),
  Situation(id: 'dark', label: '어둠이 무서워요', kind: SituationKind.parenting, emoji: '💡'),
  Situation(id: 'sibling', label: '동생이 생겼어요', kind: SituationKind.parenting, emoji: '👶'),
  Situation(id: 'veggies', label: '골고루 먹기', kind: SituationKind.parenting, emoji: '🥕'),
  // Adventure / theme
  Situation(id: 'animals', label: '동물 친구들', kind: SituationKind.theme, emoji: '🐰'),
  Situation(id: 'space', label: '우주 여행', kind: SituationKind.theme, emoji: '🚀'),
  Situation(id: 'ocean', label: '바닷속 모험', kind: SituationKind.theme, emoji: '🐚'),
  Situation(id: 'forest', label: '숲속 이야기', kind: SituationKind.theme, emoji: '🌳'),
  Situation(id: 'dino', label: '공룡 나라', kind: SituationKind.theme, emoji: '🦕'),
  Situation(id: 'magic', label: '마법 세계', kind: SituationKind.theme, emoji: '✨'),
];
