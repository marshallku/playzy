import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/sdui/sdui_models.dart';

void main() {
  group('SduiDocument.fromJson', () {
    test('parses known components', () {
      final doc = SduiDocument.fromJson({
        'schemaVersion': 1,
        'components': [
          {'type': 'section', 'title': '제목'},
          {
            'type': 'chip_group',
            'chips': [
              {'id': 'bedtime', 'label': '잠자기', 'emoji': '🌙'},
            ],
          },
          {'type': 'banner', 'text': '안내'},
          {'type': 'spacer', 'size': 'xl'},
        ],
      });

      expect(doc.schemaVersion, 1);
      expect(doc.components, hasLength(4));
      expect(doc.components[0], isA<SduiSection>());
      final group = doc.components[1] as SduiChipGroup;
      expect(group.chips.single.id, 'bedtime');
      expect(group.chips.single.emoji, '🌙');
      expect(doc.components[2], isA<SduiBanner>());
      expect((doc.components[3] as SduiSpacer).size, SduiSpace.xl);
    });

    test('spacer size is a whitelisted token; junk falls back to md', () {
      final doc = SduiDocument.fromJson({
        'components': [
          {'type': 'spacer', 'size': 'NaN'},
          {'type': 'spacer'},
        ],
      });
      expect((doc.components[0] as SduiSpacer).size, SduiSpace.md);
      expect((doc.components[1] as SduiSpacer).size, SduiSpace.md);
    });

    test('unknown component types degrade to SduiUnknown (forward compatible)', () {
      final doc = SduiDocument.fromJson({
        'schemaVersion': 1,
        'components': [
          {'type': 'carousel_3d', 'wild': true},
          {'type': 'section', 'title': 'ok'},
        ],
      });
      expect(doc.components[0], isA<SduiUnknown>());
      expect((doc.components[0] as SduiUnknown).type, 'carousel_3d');
      expect(doc.components[1], isA<SduiSection>());
    });

    test('defaults version and tolerates missing components', () {
      final doc = SduiDocument.fromJson({});
      expect(doc.schemaVersion, 1);
      expect(doc.components, isEmpty);
    });

    test('round-trips known components through JSON', () {
      const original = SduiDocument(
        schemaVersion: 1,
        components: [
          SduiSection(title: '제목'),
          SduiChipGroup(chips: [SduiChip(id: 'a', label: 'A', emoji: '⭐')]),
        ],
      );
      final decoded = SduiDocument.fromJson(original.toJson());
      expect(decoded.schemaVersion, 1);
      expect((decoded.components[0] as SduiSection).title, '제목');
      expect((decoded.components[1] as SduiChipGroup).chips.single.label, 'A');
    });
  });
}
