import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/data/auth/auth_session.dart';

void main() {
  group('AuthSession', () {
    test('round-trips through JSON', () {
      const session = AuthSession(token: 't', accountId: 'acct_1');
      expect(AuthSession.fromJson(session.toJson()), session);
    });

    test('a partial or blank record is treated as no session', () {
      expect(AuthSession.fromJson({'token': 'only-token'}), isNull);
      expect(AuthSession.fromJson({'accountId': 'only-account'}), isNull);
      expect(AuthSession.fromJson({'token': '', 'accountId': 'a'}), isNull);
      expect(AuthSession.fromJson({'token': 't', 'accountId': ''}), isNull);
      expect(AuthSession.fromJson(const {}), isNull);
    });
  });
}
