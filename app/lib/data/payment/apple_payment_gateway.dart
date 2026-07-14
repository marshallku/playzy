import 'payment_gateway.dart';
import 'rc_client.dart';

/// Apple IAP gateway backed by RevenueCat (ADR 0002 / D1). Credit packs are
/// **consumables**: a purchase yields a transaction that RevenueCat reports to the
/// backend via webhook, which credits the account. This gateway therefore NEVER
/// grants credits locally — it only drives the native purchase and reports success.
class ApplePaymentGateway implements PaymentGateway {
  ApplePaymentGateway(
    this._rc, {
    required String apiKey,
    required String appUserId,
  })  : _apiKey = apiKey,
        _appUserId = appUserId;

  final RcClient _rc;
  final String _apiKey;
  final String _appUserId;

  // Lazy, idempotent SDK init — configuration is async, so gate first use on it
  // rather than racing a fire-and-forget configure in the provider.
  Future<void>? _ready;
  Future<void> _ensureConfigured() => _ready ??= _rc.configure(_apiKey, _appUserId);

  @override
  Future<List<Product>> getProducts(List<String> ids) async {
    await _ensureConfigured();
    final products = await _rc.products(ids);
    return products
        .map((p) => Product(
              id: p.id,
              type: PurchaseType.consumable,
              amountMinor: minorUnitsForPrice(p.price, p.currency),
              currency: p.currency,
            ))
        .toList();
  }

  @override
  Future<PurchaseResult> purchase(Product product) async {
    if (product.type != PurchaseType.consumable) {
      throw ArgumentError(
        'purchase() requires a consumable product, got ${product.type.name}',
      );
    }
    await _ensureConfigured();
    try {
      final result = await _rc.purchase(product.id);
      // No entitlementId: consumables are not durable entitlements. No local
      // credit grant: the backend webhook owns the balance.
      return PurchaseResult(success: true, transactionRef: result.transactionId);
    } on RcPurchaseCancelled {
      // Expected user action — not an error. The caller leaves the paywall open.
      return const PurchaseResult(success: false);
    }
  }

  @override
  Future<PurchaseResult> subscribe(Product product) async {
    throw UnsupportedError('Playzy sells consumable credit packs only (D1)');
  }

  @override
  Future<void> restorePurchases() async {
    await _ensureConfigured();
    await _rc.restore();
  }

  @override
  Future<Set<String>> activeEntitlements() async {
    await _ensureConfigured();
    return _rc.activeEntitlements();
  }

  @override
  Stream<Set<String>> entitlementChanges() => _rc.entitlementUpdates();
}

/// Zero-decimal ISO-4217 currencies (no minor unit — the "minor" amount IS the
/// whole-currency amount). Covers the ones we might price in; others default to 2
/// decimals. Display-advisory only (the paywall label is fixed; the store + server
/// own the real price), so exotic 3-decimal currencies are intentionally not modeled.
const _zeroDecimalCurrencies = {
  'KRW', 'JPY', 'VND', 'CLP', 'ISK', 'UGX', 'XAF', 'XOF',
  'PYG', 'RWF', 'KMF', 'DJF', 'GNF', 'BIF', 'VUV', 'XPF',
};

/// Converts a localized major-unit [price] (e.g. 4900.0 KRW, 4.99 USD) into the
/// currency's minor unit for the domain `Product.amountMinor` (₩4,900 → 4900,
/// $4.99 → 499). Advisory display value only.
int minorUnitsForPrice(double price, String currency) {
  final zeroDecimal = _zeroDecimalCurrencies.contains(currency.toUpperCase());
  return (price * (zeroDecimal ? 1 : 100)).round();
}
