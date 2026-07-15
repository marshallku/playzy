import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/auth_controller.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/payment/fake_payment_gateway.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/features/auth/login_screen.dart';

import '../../support/auth_fakes.dart';

ProviderContainer _pump(
  WidgetTester tester, {
  FakeAuthApi? api,
  FakeSocialSignIn? social,
  FakeSessionStore? store,
}) {
  final gw = FakePaymentGateway();
  addTearDown(gw.dispose);
  final container = ProviderContainer(overrides: [
    deviceIdProvider.overrideWithValue('dev-1'),
    authApiProvider.overrideWithValue(api ?? FakeAuthApi()),
    socialSignInProvider.overrideWithValue(social ?? FakeSocialSignIn()),
    secureSessionStoreProvider.overrideWithValue(store ?? FakeSessionStore()),
    paymentGatewayProvider.overrideWithValue(gw),
    profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpScreen(
    WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: LoginScreen()),
  ));
}

void main() {
  group('LoginScreen', () {
    testWidgets('renders the three provider buttons', (tester) async {
      final c = _pump(tester);
      await _pumpScreen(tester, c);
      expect(find.text('Apple로 계속하기'), findsOneWidget);
      expect(find.text('Google로 계속하기'), findsOneWidget);
      expect(find.text('카카오로 계속하기'), findsOneWidget);
    });

    testWidgets('a successful sign-in signs the user in', (tester) async {
      final c = _pump(tester);
      await _pumpScreen(tester, c);

      await tester.tap(find.text('Google로 계속하기'));
      await tester.pumpAndSettle();

      expect(c.read(authControllerProvider).isSignedIn, isTrue);
    });

    testWidgets('a failed sign-in shows an error and stays signed out',
        (tester) async {
      final c = _pump(tester, social: FakeSocialSignIn(fail: true));
      await _pumpScreen(tester, c);

      await tester.tap(find.text('카카오로 계속하기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('로그인에 실패했어요'), findsOneWidget);
      expect(c.read(authControllerProvider).isSignedIn, isFalse);
    });
  });
}
