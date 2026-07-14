import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/payment/fake_payment_gateway.dart';
import 'package:playzy/data/profile/profile_repository.dart';
import 'package:playzy/features/paywall/paywall_screen.dart';

Future<ProviderContainer> _pumpPaywall(
  WidgetTester tester,
  PaymentMode mode, {
  int credits = 0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentModeProvider.overrideWithValue(mode),
        paymentGatewayProvider.overrideWithValue(FakePaymentGateway()),
        profileRepositoryProvider
            .overrideWithValue(FakeProfileRepository(credits: credits)),
      ],
      child: const MaterialApp(home: PaywallScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(PaywallScreen)));
}

void main() {
  group('PaywallScreen settlement', () {
    testWidgets('offline mode grants to the local credit mirror', (tester) async {
      final container = await _pumpPaywall(tester, PaymentMode.offlineLocal);

      await tester.tap(find.text('동화 10편 이용권 · 4,900원'));
      await tester.pumpAndSettle();

      expect(await container.read(creditsProvider.future), 10);
    });

    testWidgets('real Apple mode shows the pending (webhook) message', (tester) async {
      await _pumpPaywall(tester, PaymentMode.appleWebhook);

      await tester.tap(find.text('동화 10편 이용권 · 4,900원'));
      await tester.pumpAndSettle();

      expect(find.text('구매가 완료됐어요. 크레딧이 곧 반영돼요.'), findsOneWidget);
    });

    testWidgets('backend-without-grant-path tells the user it is not ready', (tester) async {
      await _pumpPaywall(tester, PaymentMode.unavailable);

      await tester.tap(find.text('동화 10편 이용권 · 4,900원'));
      await tester.pumpAndSettle();

      expect(find.text('이 빌드에서는 결제가 아직 준비되지 않았어요.'), findsOneWidget);
    });
  });
}
