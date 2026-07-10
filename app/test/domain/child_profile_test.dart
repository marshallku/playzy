import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/domain/child_profile.dart';

void main() {
  group('ChildProfile', () {
    const profile = ChildProfile(
      id: 'c1',
      name: '하준',
      ageBand: AgeBand.toddler,
      interests: ['공룡', '자동차'],
      companionName: '누나',
    );

    test('JSON round-trips without loss', () {
      final decoded = ChildProfile.fromJson(profile.toJson());
      expect(decoded, profile);
      expect(decoded.interests, ['공룡', '자동차']);
      expect(decoded.companionName, '누나');
    });

    test('encode/decode string round-trips', () {
      expect(ChildProfile.decode(profile.encode()), profile);
    });

    test('copyWith preserves id and overrides fields', () {
      final updated = profile.copyWith(name: '서연', ageBand: AgeBand.preschool);
      expect(updated.id, 'c1');
      expect(updated.name, '서연');
      expect(updated.ageBand, AgeBand.preschool);
      expect(updated.interests, profile.interests);
    });

    test('copyWith(clearCompanionName) clears the optional companion', () {
      final cleared = profile.copyWith(clearCompanionName: true);
      expect(cleared.companionName, isNull);
      // A plain copyWith without the flag keeps the existing value.
      expect(profile.copyWith(name: 'x').companionName, '누나');
    });

    test('interests default to empty and omitted companion is null', () {
      final decoded = ChildProfile.fromJson({
        'id': 'c2',
        'name': '아이',
        'ageBand': 'infant',
      });
      expect(decoded.interests, isEmpty);
      expect(decoded.companionName, isNull);
    });

    test('equality ignores interest ordering only when identical', () {
      const a = ChildProfile(id: 'x', name: 'n', ageBand: AgeBand.infant, interests: ['a', 'b']);
      const b = ChildProfile(id: 'x', name: 'n', ageBand: AgeBand.infant, interests: ['b', 'a']);
      expect(a == b, isFalse);
    });

    test('every age band exposes a Korean label', () {
      for (final band in AgeBand.values) {
        expect(band.label, isNotEmpty);
      }
    });
  });
}
