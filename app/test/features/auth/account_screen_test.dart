import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/auth_controller.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/auth/auth_session.dart';
import 'package:playzy/data/payment/fake_payment_gateway.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/features/auth/account_screen.dart';

import '../../support/auth_fakes.dart';

const _session = AuthSession(token: 'tok-1', accountId: 'acct_1');

ProviderContainer _pump(
  WidgetTester tester, {
  FakeAuthApi? api,
  FakeSessionStore? store,
  AuthSession? initial,
}) {
  final gw = FakePaymentGateway();
  addTearDown(gw.dispose);
  final container = ProviderContainer(overrides: [
    deviceIdProvider.overrideWithValue('dev-1'),
    authApiProvider.overrideWithValue(api ?? FakeAuthApi()),
    socialSignInProvider.overrideWithValue(FakeSocialSignIn()),
    secureSessionStoreProvider.overrideWithValue(store ?? FakeSessionStore()),
    paymentGatewayProvider.overrideWithValue(gw),
    profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
    initialSessionProvider.overrideWithValue(initial),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpScreen(
    WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: AccountScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('AccountScreen', () {
    testWidgets('signed out shows the login CTA, not account actions',
        (tester) async {
      final c = _pump(tester); // initial null → signed out
      await _pumpScreen(tester, c);
      expect(find.text('로그인'), findsOneWidget);
      expect(find.text('로그아웃'), findsNothing);
      expect(find.text('계정 삭제'), findsNothing);
    });

    testWidgets('signed in shows logout and delete', (tester) async {
      final c = _pump(tester, initial: _session);
      await _pumpScreen(tester, c);
      expect(find.text('로그아웃'), findsOneWidget);
      expect(find.text('계정 삭제'), findsOneWidget);
    });

    testWidgets('logout signs the user out', (tester) async {
      final c = _pump(tester,
          store: FakeSessionStore()..stored = _session, initial: _session);
      await _pumpScreen(tester, c);

      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();

      expect(c.read(authControllerProvider).isSignedIn, isFalse);
    });

    testWidgets('delete confirms, calls the backend, then signs out',
        (tester) async {
      final api = FakeAuthApi();
      final c = _pump(tester,
          api: api,
          store: FakeSessionStore()..stored = _session,
          initial: _session);
      await _pumpScreen(tester, c);

      await tester.tap(find.text('계정 삭제'));
      await tester.pumpAndSettle();
      expect(find.text('계정을 삭제할까요?'), findsOneWidget); // confirm dialog

      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(api.deletedToken, 'tok-1');
      expect(c.read(authControllerProvider).isSignedIn, isFalse);
    });

    testWidgets('cancelling the delete dialog keeps the account',
        (tester) async {
      final api = FakeAuthApi();
      final c = _pump(tester,
          api: api,
          store: FakeSessionStore()..stored = _session,
          initial: _session);
      await _pumpScreen(tester, c);

      await tester.tap(find.text('계정 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(api.deletedToken, isNull);
      expect(c.read(authControllerProvider).isSignedIn, isTrue);
    });

    testWidgets(
        'a delete whose local clear fails surfaces the error (no silent success)',
        (tester) async {
      final api = FakeAuthApi();
      // Backend delete succeeds, but clearing the session store throws. Delete uses the
      // same required-clears semantics as sign-out, so it fails loud rather than
      // reporting success or leaving a leak; the transient signed-in state self-heals
      // via the 401 handler + hydration on next launch.
      final c = _pump(
        tester,
        api: api,
        store: FakeSessionStore(failClear: true)..stored = _session,
        initial: _session,
      );
      await _pumpScreen(tester, c);

      await tester.tap(find.text('계정 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(api.deletedToken, 'tok-1'); // backend delete did happen
      expect(find.textContaining('계정 삭제에 실패했어요'),
          findsOneWidget); // surfaced, not silent
    });
  });
}
