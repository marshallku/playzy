import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/domain/child_profile.dart';

void main() {
  group('ChildProfile', () {
    const profile = ChildProfile(
      id: 'c1',
      familyName: '김',
      givenName: '하준',
      ageBand: AgeBand.toddler,
      interests: ['공룡', '자동차'],
      companionName: '누나',
    );

    test('JSON round-trips without loss', () {
      final decoded = ChildProfile.fromJson(profile.toJson());
      expect(decoded, profile);
      expect(decoded.givenName, '하준');
      expect(decoded.familyName, '김');
      expect(decoded.interests, ['공룡', '자동차']);
      expect(decoded.companionName, '누나');
    });

    test('encode/decode string round-trips', () {
      expect(ChildProfile.decode(profile.encode()), profile);
    });

    test('legacy single `name` migrates to givenName verbatim', () {
      // Pre-split profiles stored one `name`; it becomes the given name (auto-
      // splitting a surname is unreliable), and family name stays null.
      final decoded = ChildProfile.fromJson({
        'id': 'c2',
        'name': '하준',
        'ageBand': 'toddler',
      });
      expect(decoded.givenName, '하준');
      expect(decoded.familyName, isNull);
    });

    test('toJson keeps companionName so the roster can migrate it (C2)', () {
      expect(profile.toJson()['companionName'], '누나');
      // givenName is written under the new key, not the legacy `name`.
      expect(profile.toJson()['givenName'], '하준');
      expect(profile.toJson().containsKey('name'), isFalse);
    });

    test('copyWith preserves id and overrides fields', () {
      final updated = profile.copyWith(givenName: '서연', ageBand: AgeBand.preschool);
      expect(updated.id, 'c1');
      expect(updated.givenName, '서연');
      expect(updated.familyName, '김'); // preserved
      expect(updated.ageBand, AgeBand.preschool);
      expect(updated.interests, profile.interests);
    });

    test('copyWith(clearFamilyName) clears the optional family name', () {
      expect(profile.copyWith(clearFamilyName: true).familyName, isNull);
      expect(profile.copyWith(givenName: 'x').familyName, '김'); // kept without the flag
    });

    test('interests default to empty and omitted family/companion are null', () {
      final decoded = ChildProfile.fromJson({
        'id': 'c2',
        'givenName': '아이',
        'ageBand': 'infant',
      });
      expect(decoded.interests, isEmpty);
      expect(decoded.familyName, isNull);
      expect(decoded.companionName, isNull);
    });

    test('equality ignores interest ordering only when identical', () {
      const a = ChildProfile(id: 'x', givenName: 'n', ageBand: AgeBand.infant, interests: ['a', 'b']);
      const b = ChildProfile(id: 'x', givenName: 'n', ageBand: AgeBand.infant, interests: ['b', 'a']);
      expect(a == b, isFalse);
    });

    test('every age band exposes a Korean label', () {
      for (final band in AgeBand.values) {
        expect(band.label, isNotEmpty);
      }
    });
  });
}
