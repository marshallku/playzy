import 'dart:async';

import 'payment_gateway.dart';

/// Dev/test implementation of [PaymentGateway] (ADR 0002). Grants entitlements
/// locally so the paywall + gating UI can be built and tested before any real
/// provider (Apple IAP / Toss) is wired. No real money moves.
class FakePaymentGateway implements PaymentGateway {
  FakePaymentGateway({Set<String> initialEntitlements = const {}})
      : _entitlements = {...initialEntitlements};

  final Set<String> _entitlements;
  final _controller = StreamController<Set<String>>.broadcast();

  /// Backend-owned credit balance, modeled locally for the fake. Consumable
  /// purchases accumulate here (buying twice adds twice) — they are NOT durable
  /// entitlements (ADR 0002 / PaymentGateway doc).
  int _creditBalance = 0;
  int _txCounter = 0;

  /// Test-only view of the accumulated consumable credit balance.
  int get creditBalance => _creditBalance;

  /// How many credits each consumable product grants (backend config in real life).
  static const Map<String, int> _creditAmounts = {'credits_10': 10};

  static const Map<String, Product> _catalog = {
    'pro_monthly': Product(
      id: 'pro_monthly',
      type: PurchaseType.subscription,
      amountMinor: 5900,
      currency: 'KRW',
    ),
    'credits_10': Product(
      id: 'credits_10',
      type: PurchaseType.consumable,
      amountMinor: 4900,
      currency: 'KRW',
    ),
  };

  /// The last subject set via [setUserId] — lets tests assert identity alignment.
  String? lastUserId;

  @override
  Future<void> setUserId(String subject) async {
    lastUserId = subject;
  }

  @override
  Future<List<Product>> getProducts(List<String> ids) async =>
      ids.map((id) => _catalog[id]).whereType<Product>().toList();

  @override
  Future<PurchaseResult> purchase(Product product) async {
    _requireType(product, PurchaseType.consumable, 'purchase');
    // Consumable → accumulate credit balance; never a durable entitlement.
    _creditBalance += _creditAmounts[product.id] ?? 0;
    return PurchaseResult(success: true, transactionRef: 'fake-tx-${_txCounter++}');
  }

  @override
  Future<PurchaseResult> subscribe(Product product) async {
    _requireType(product, PurchaseType.subscription, 'subscribe');
    // Subscription → durable entitlement.
    _entitlements.add(product.id);
    _controller.add({..._entitlements});
    return PurchaseResult(success: true, transactionRef: 'fake-tx-${_txCounter++}', entitlementId: product.id);
  }

  /// Enforce the contract: purchase() is consumables-only, subscribe() is
  /// subscriptions-only — a real gateway must reject the mismatch too.
  void _requireType(Product product, PurchaseType expected, String method) {
    if (product.type != expected) {
      throw ArgumentError('$method() requires a ${expected.name} product, got ${product.type.name}');
    }
  }

  @override
  Future<void> restorePurchases() async => _controller.add({..._entitlements});

  @override
  Future<Set<String>> activeEntitlements() async => {..._entitlements};

  @override
  Stream<Set<String>> entitlementChanges() => _controller.stream;

  /// Test helper — release the broadcast controller.
  Future<void> dispose() => _controller.close();
}
