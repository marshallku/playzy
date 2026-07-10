// Payment abstraction (ADR 0002). The interface speaks in products,
// purchases, and entitlements — never in provider mechanics (paymentKey /
// receipt / confirm), which live inside implementations and the backend.
// iOS binds to an Apple-IAP (RevenueCat) impl; web/Android to a Toss impl.

/// Credit pack (consumable) vs subscription (정기결제).
enum PurchaseType { consumable, subscription }

class Product {
  const Product({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.currency,
  });

  /// App Store product id OR Toss orderName — opaque above the interface.
  final String id;
  final PurchaseType type;

  /// Display amount in the currency's minor unit (e.g. KRW has no minor unit,
  /// so this is the whole-won amount). Source of truth stays server-side.
  final int amountMinor;
  final String currency;
}

class PurchaseResult {
  const PurchaseResult({required this.success, this.transactionRef, this.entitlementId});

  final bool success;

  /// StoreKit transactionId OR Toss paymentKey — opaque, for logging only.
  final String? transactionRef;

  /// Granted entitlement, e.g. "pro_monthly" / "credits_50".
  final String? entitlementId;
}

abstract interface class PaymentGateway {
  Future<List<Product>> getProducts(List<String> ids);

  /// One-shot purchase of a [PurchaseType.consumable] credit pack. Yields a
  /// transaction the **backend** redeems into the account's credit balance
  /// (ADR 0002 — the balance is backend-owned, so buying twice accumulates).
  /// Consumables are NOT durable entitlements and do not appear in
  /// [activeEntitlements].
  Future<PurchaseResult> purchase(Product product);

  /// Recurring [PurchaseType.subscription]. Grants a durable entitlement that
  /// does appear in [activeEntitlements].
  Future<PurchaseResult> subscribe(Product product);

  /// Required by Apple 3.1.1.
  Future<void> restorePurchases();

  /// DURABLE entitlements only (active subscriptions / one-time unlocks). The
  /// backend is the source of truth; this reflects it. Consumable credit
  /// balances live in the backend and are surfaced via the story quota API,
  /// not here.
  Future<Set<String>> activeEntitlements();

  Stream<Set<String>> entitlementChanges();
}
