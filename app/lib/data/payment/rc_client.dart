import 'dart:async';

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Thin seam over RevenueCat's static `Purchases` API so [ApplePaymentGateway] is
/// unit-testable with a fake — no StoreKit, no plugin, in tests. Only the calls the
/// gateway needs are exposed; everything provider-specific stays behind here.
abstract interface class RcClient {
  /// Idempotent SDK init. Awaitable so callers can gate first use on readiness
  /// (`Purchases.configure` is async).
  Future<void> configure(String apiKey, String appUserId);

  /// Fetch consumable products by id.
  Future<List<RcProduct>> products(List<String> ids);

  /// Purchase a consumable. Throws [RcPurchaseCancelled] when the user cancels;
  /// any other failure propagates as-is.
  Future<RcPurchase> purchase(String productId);

  /// Apple 3.1.1 restore.
  Future<void> restore();

  /// Durable entitlement keys currently active (empty for a consumable-only app).
  Future<Set<String>> activeEntitlements();

  /// Emits whenever RevenueCat reports a customer-info change.
  Stream<Set<String>> entitlementUpdates();
}

/// A store product, reduced to what the gateway maps into the domain `Product`.
class RcProduct {
  const RcProduct({required this.id, required this.price, required this.currency});
  final String id;

  /// Localized price in major currency units (e.g. 4900.0 for ₩4,900). The
  /// authoritative amount lives server-side; this is display-advisory only.
  final double price;
  final String currency;
}

/// The outcome of a successful purchase. [transactionId] is best-effort and used
/// only for logging — the backend credits the account from RevenueCat's webhook
/// keyed on its own store transaction id, not this value.
class RcPurchase {
  const RcPurchase(this.transactionId);
  final String? transactionId;
}

/// The user dismissed the native purchase sheet — an expected outcome, not an error.
class RcPurchaseCancelled implements Exception {
  const RcPurchaseCancelled();
}

/// Real RevenueCat-backed client. Not imported by tests. Guard construction behind
/// the payment mode so it only runs where RevenueCat is actually configured.
class RevenueCatClient implements RcClient {
  final _entitlements = StreamController<Set<String>>.broadcast();
  Future<void>? _ready;
  CustomerInfoUpdateListener? _listener;

  @override
  Future<void> configure(String apiKey, String appUserId) {
    return _ready ??= _configure(apiKey, appUserId);
  }

  Future<void> _configure(String apiKey, String appUserId) async {
    await Purchases.configure(PurchasesConfiguration(apiKey)..appUserID = appUserId);
    if (_listener == null) {
      // Retain the callback so dispose can deregister it — otherwise the SDK could
      // invoke it after the controller is closed and throw an async StateError.
      _listener = (info) {
        if (!_entitlements.isClosed) {
          _entitlements.add(info.entitlements.active.keys.toSet());
        }
      };
      Purchases.addCustomerInfoUpdateListener(_listener!);
    }
  }

  @override
  Future<List<RcProduct>> products(List<String> ids) async {
    final products = await Purchases.getProducts(
      ids,
      productCategory: ProductCategory.nonSubscription,
    );
    return products
        .map((p) => RcProduct(id: p.identifier, price: p.price, currency: p.currencyCode))
        .toList();
  }

  @override
  Future<RcPurchase> purchase(String productId) async {
    final products = await Purchases.getProducts(
      [productId],
      productCategory: ProductCategory.nonSubscription,
    );
    if (products.isEmpty) {
      throw StateError('RevenueCat has no consumable product "$productId"');
    }
    try {
      final info = await Purchases.purchaseStoreProduct(products.first);
      final matching = info.nonSubscriptionTransactions
          .where((t) => t.productIdentifier == productId)
          .toList();
      final txnId = matching.isNotEmpty ? matching.last.transactionIdentifier : null;
      return RcPurchase(txnId);
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        throw const RcPurchaseCancelled();
      }
      rethrow;
    }
  }

  @override
  Future<void> restore() => Purchases.restorePurchases();

  @override
  Future<Set<String>> activeEntitlements() async {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.keys.toSet();
  }

  @override
  Stream<Set<String>> entitlementUpdates() => _entitlements.stream;

  void dispose() {
    final listener = _listener;
    if (listener != null) {
      Purchases.removeCustomerInfoUpdateListener(listener);
      _listener = null;
    }
    _entitlements.close();
  }
}
