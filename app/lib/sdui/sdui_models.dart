// Server-Driven UI models (ADR 0003 Tier A). A small, whitelisted component
// vocabulary the backend can rearrange without an app release. Every component
// renders as a design-system widget; unknown types degrade gracefully.

/// A parsed SDUI screen. [schemaVersion] lets the app reject/ignore documents
/// it's too old to understand.
class SduiDocument {
  const SduiDocument({required this.schemaVersion, required this.components});

  final int schemaVersion;
  final List<SduiComponent> components;

  /// The renderer version this app build supports.
  static const int supportedVersion = 1;

  factory SduiDocument.fromJson(Map<String, dynamic> json) {
    final version = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    final raw = (json['components'] as List<dynamic>? ?? const []);
    return SduiDocument(
      schemaVersion: version,
      components: raw
          .map((e) => SduiComponent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'components': components.map((c) => c.toJson()).toList(),
      };
}

/// Base type. Unknown `type` values parse to [SduiUnknown] so a newer backend
/// component never crashes an older app — the renderer simply skips it.
sealed class SduiComponent {
  const SduiComponent();

  factory SduiComponent.fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String?) {
      case 'section':
        return SduiSection(title: json['title'] as String? ?? '');
      case 'chip_group':
        return SduiChipGroup(
          chips: (json['chips'] as List<dynamic>? ?? const [])
              .map((e) => SduiChip.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'banner':
        return SduiBanner(text: json['text'] as String? ?? '');
      case 'spacer':
        return SduiSpacer(size: SduiSpace.parse(json['size'] as String?));
      default:
        return SduiUnknown(type: json['type'] as String? ?? 'null');
    }
  }

  Map<String, dynamic> toJson();
}

class SduiSection extends SduiComponent {
  const SduiSection({required this.title});
  final String title;

  @override
  Map<String, dynamic> toJson() => {'type': 'section', 'title': title};
}

class SduiChipGroup extends SduiComponent {
  const SduiChipGroup({required this.chips});
  final List<SduiChip> chips;

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'chip_group', 'chips': chips.map((c) => c.toJson()).toList()};
}

class SduiBanner extends SduiComponent {
  const SduiBanner({required this.text});
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'banner', 'text': text};
}

/// Whitelisted spacer sizes — server input is a token name, never a raw
/// number, so it can't inject NaN/infinity/huge values (maps to AppSpacing in
/// the renderer).
enum SduiSpace {
  sm,
  md,
  lg,
  xl,
  xxl;

  static SduiSpace parse(String? name) =>
      SduiSpace.values.asNameMap()[name] ?? SduiSpace.md;
}

class SduiSpacer extends SduiComponent {
  const SduiSpacer({required this.size});
  final SduiSpace size;

  @override
  Map<String, dynamic> toJson() => {'type': 'spacer', 'size': size.name};
}

/// An unrecognized component — rendered as nothing (forward compatibility).
class SduiUnknown extends SduiComponent {
  const SduiUnknown({required this.type});
  final String type;

  @override
  Map<String, dynamic> toJson() => {'type': type};
}

/// A selectable chip inside a [SduiChipGroup]. [id] is what selection tracks.
class SduiChip {
  const SduiChip({required this.id, required this.label, this.emoji});

  final String id;
  final String label;
  final String? emoji;

  factory SduiChip.fromJson(Map<String, dynamic> json) => SduiChip(
        id: json['id'] as String,
        label: json['label'] as String,
        emoji: json['emoji'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (emoji != null) 'emoji': emoji,
      };
}
