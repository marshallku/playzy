import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/data/payment/apple_payment_gateway.dart';
import 'package:playzy/data/payment/payment_gateway.dart';
import 'package:playzy/data/payment/rc_client.dart';

/// Records calls and returns scripted results, so the gateway is exercised without
/// StoreKit or the RevenueCat plugin.
class FakeRcClient implements RcClient {
  FakeRcClient({
    this.catalog = const {'credits_10': RcProduct(id: 'credits_10', price: 4900, currency: 'KRW')},
    this.purchaseResult = const RcPurchase('txn-1'),
    this.cancel = false,
  });

  final Map<String, RcProduct> catalog;
  final RcPurchase purchaseResult;
  final bool cancel;

  int configureCalls = 0;
  final List<String> purchased = [];
  final _entitlements = StreamController<Set<String>>.broadcast();

  @override
  Future<void> configure(String apiKey, String appUserId) async {
    configureCalls++;
  }

  @override
  Future<List<RcProduct>> products(List<String> ids) async =>
      ids.map((id) => catalog[id]).whereType<RcProduct>().toList();

  @override
  Future<RcPurchase> purchase(String productId) async {
    if (cancel) throw const RcPurchaseCancelled();
    purchased.add(productId);
    return purchaseResult;
  }

  @override
  Future<void> restore() async {}

  @override
  Future<Set<String>> activeEntitlements() async => const {};

  @override
  Stream<Set<String>> entitlementUpdates() => _entitlements.stream;

  void dispose() => _entitlements.close();
}

ApplePaymentGateway _gateway(FakeRcClient rc) =>
    ApplePaymentGateway(rc, apiKey: 'appl_test', appUserId: 'device-1');

void main() {
  group('ApplePaymentGateway', () {
    test('is a PaymentGateway', () {
      expect(_gateway(FakeRcClient()), isA<PaymentGateway>());
    });

    test('maps store products to consumable domain products', () async {
      final gw = _gateway(FakeRcClient());
      final products = await gw.getProducts(['credits_10']);
      expect(products.single.id, 'credits_10');
      expect(products.single.type, PurchaseType.consumable);
      expect(products.single.currency, 'KRW');
      expect(products.single.amountMinor, 4900); // KRW is zero-decimal
    });

    test('purchase reports success + transactionRef, no entitlement, no local grant', () async {
      final rc = FakeRcClient();
      final gw = _gateway(rc);
      final product = (await gw.getProducts(['credits_10'])).single;

      final result = await gw.purchase(product);
      expect(result.success, isTrue);
      expect(result.transactionRef, 'txn-1');
      // Consumables are never durable entitlements, and the gateway must not grant
      // locally — the backend webhook owns the balance.
      expect(result.entitlementId, isNull);
      expect(rc.purchased, ['credits_10']);
    });

    test('lazily configures once across calls', () async {
      final rc = FakeRcClient();
      final gw = _gateway(rc);
      await gw.getProducts(['credits_10']);
      await gw.purchase((await gw.getProducts(['credits_10'])).single);
      expect(rc.configureCalls, 1);
    });

    test('user cancel is a non-error unsuccessful result', () async {
      final gw = _gateway(FakeRcClient(cancel: true));
      final product = const Product(
        id: 'credits_10',
        type: PurchaseType.consumable,
        amountMinor: 4900,
        currency: 'KRW',
      );
      final result = await gw.purchase(product);
      expect(result.success, isFalse);
    });

    test('rejects a non-consumable product (contract enforcement)', () async {
      final gw = _gateway(FakeRcClient());
      final sub = const Product(
        id: 'pro_monthly',
        type: PurchaseType.subscription,
        amountMinor: 5900,
        currency: 'KRW',
      );
      expect(() => gw.purchase(sub), throwsArgumentError);
    });

    test('subscribe is unsupported (credit packs only)', () async {
      final gw = _gateway(FakeRcClient());
      final product = const Product(
        id: 'credits_10',
        type: PurchaseType.consumable,
        amountMinor: 4900,
        currency: 'KRW',
      );
      expect(() => gw.subscribe(product), throwsUnsupportedError);
    });
  });

  group('minorUnitsForPrice', () {
    test('zero-decimal currencies use whole units', () {
      expect(minorUnitsForPrice(4900, 'KRW'), 4900);
      expect(minorUnitsForPrice(500, 'JPY'), 500);
      expect(minorUnitsForPrice(4900, 'krw'), 4900); // case-insensitive
    });

    test('two-decimal currencies scale by 100', () {
      expect(minorUnitsForPrice(4.99, 'USD'), 499);
      expect(minorUnitsForPrice(9.90, 'EUR'), 990);
    });
  });
}
