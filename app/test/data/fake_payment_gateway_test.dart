import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/data/payment/fake_payment_gateway.dart';
import 'package:playzy/data/payment/payment_gateway.dart';

void main() {
  group('FakePaymentGateway', () {
    test('implements the PaymentGateway seam', () {
      expect(FakePaymentGateway(), isA<PaymentGateway>());
    });

    test('starts with no entitlements and grants on subscribe', () async {
      final gw = FakePaymentGateway();
      addTearDown(gw.dispose);

      expect(await gw.activeEntitlements(), isEmpty);

      final products = await gw.getProducts(['pro_monthly']);
      expect(products.single.type, PurchaseType.subscription);

      final result = await gw.subscribe(products.single);
      expect(result.success, isTrue);
      expect(result.entitlementId, 'pro_monthly');
      expect(await gw.activeEntitlements(), contains('pro_monthly'));
    });

    test('consumable purchase accumulates credit balance, not a durable entitlement', () async {
      final gw = FakePaymentGateway();
      addTearDown(gw.dispose);

      final products = await gw.getProducts(['credits_10']);
      expect(products.single.type, PurchaseType.consumable);

      final r1 = await gw.purchase(products.single);
      final r2 = await gw.purchase(products.single);

      // Buying twice accumulates (10 + 10) and is NOT a durable entitlement.
      expect(gw.creditBalance, 20);
      expect(await gw.activeEntitlements(), isNot(contains('credits_10')));
      expect(r1.transactionRef, isNot(r2.transactionRef));
      expect(r1.entitlementId, isNull);
    });

    test('subscription emits a durable entitlement change', () async {
      final gw = FakePaymentGateway();
      addTearDown(gw.dispose);

      final future = gw.entitlementChanges().first;
      final products = await gw.getProducts(['pro_monthly']);
      await gw.subscribe(products.single);

      expect(await future, contains('pro_monthly'));
    });

    test('rejects product-type mismatch (contract enforcement)', () async {
      final gw = FakePaymentGateway();
      addTearDown(gw.dispose);
      final sub = (await gw.getProducts(['pro_monthly'])).single;
      final credits = (await gw.getProducts(['credits_10'])).single;

      expect(() => gw.purchase(sub), throwsArgumentError);
      expect(() => gw.subscribe(credits), throwsArgumentError);
    });

    test('honours pre-seeded entitlements', () async {
      final gw = FakePaymentGateway(initialEntitlements: {'pro_monthly'});
      addTearDown(gw.dispose);
      expect(await gw.activeEntitlements(), contains('pro_monthly'));
    });
  });
}
