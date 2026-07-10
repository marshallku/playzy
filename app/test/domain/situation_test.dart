import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/domain/situation.dart';

void main() {
  group('Situation', () {
    test('JSON round-trips', () {
      const s = Situation(id: 'bedtime', label: '잠자기', kind: SituationKind.parenting, emoji: '🌙');
      final decoded = Situation.fromJson(s.toJson());
      expect(decoded, s);
      expect(decoded.label, '잠자기');
      expect(decoded.emoji, '🌙');
    });

    test('equality is id-based', () {
      const a = Situation(id: 'x', label: 'A', kind: SituationKind.theme);
      const b = Situation(id: 'x', label: 'B different label', kind: SituationKind.parenting);
      expect(a == b, isTrue);
    });
  });

  group('default catalog', () {
    test('is non-empty and ids are unique', () {
      final ids = kDefaultSituations.map((s) => s.id).toSet();
      expect(kDefaultSituations, isNotEmpty);
      expect(ids.length, kDefaultSituations.length, reason: 'duplicate situation id');
    });

    test('leads with the parenting wedge', () {
      // The wedge (parenting situations) must come first (docs/planning/10).
      expect(kDefaultSituations.first.kind, SituationKind.parenting);
      final parenting = kDefaultSituations.where((s) => s.kind == SituationKind.parenting);
      expect(parenting.length, greaterThanOrEqualTo(6));
    });
  });
}
