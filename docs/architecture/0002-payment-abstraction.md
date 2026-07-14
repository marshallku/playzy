# ADR 0002 — Payment abstraction & iOS payment strategy

- **Status**: Accepted (with one open user decision — see below)
- **Date**: 2026-07-11
- **Evidence**: `docs/research/payments.md`

## Context

Playzy gives a few free stories, then charges. The user asked to integrate
**Toss Payments** ("연동이 가장 편한"). Research surfaced a hard conflict:

- iOS **digital** content consumed in-app **must** use Apple IAP (Guideline
  3.1.1). Toss → rejection.
- Korea's external-payment entitlement doesn't save Toss on Flutter: still 26%
  fee, **native-UI-required (WebView forbidden)**, KR-store-only, can't mix with
  IAP. The official Toss Flutter SDK is **WebView-based** → violates the rule.

So the user's stated preference (Toss on iOS) is not viable for our product on
iOS. This is exactly the "내 의사 결정이 필요한 부분은 일단 작업하되 나중에
교체하기 편한 형태로" case: build the seam, default to the viable path, keep Toss
ready for the surfaces where it *is* right.

## Decision

### 1. Everything sits behind a `PaymentGateway` interface

The interface speaks in **products, purchases, and entitlements** — never in
`paymentKey` / `confirm` / `receipt`. Those live inside each implementation and
in the backend.

```dart
enum PurchaseType { consumable, subscription }   // credit pack vs 정기결제

class Product {
  final String id;          // App Store product id OR Toss orderName
  final PurchaseType type;
  final int amountMinor;    // display only; server is source of truth
  final String currency;
}

class PurchaseResult {
  final bool success;
  final String? transactionRef;  // StoreKit transactionId OR Toss paymentKey
  final String? entitlementId;   // "pro_monthly", "credits_50"
}

abstract class PaymentGateway {
  Future<List<Product>> getProducts(List<String> ids);
  Future<PurchaseResult> purchase(Product product);     // consumable
  Future<PurchaseResult> subscribe(Product product);    // recurring
  Future<void> restorePurchases();                      // required by Apple 3.1.1
  Future<Set<String>> activeEntitlements();
  Stream<Set<String>> entitlementChanges();
}
```

### 2. Platform binding at the composition root

- **iOS →** `ApplePaymentGateway` backed by **RevenueCat** (`purchases_flutter`)
  — server-side receipt validation, entitlement sync, restore, webhooks. Credit
  packs = consumables; subscription = auto-renewable.
- **Web / Android (later) →** `TossPaymentGateway`
  (`tosspayments_widget_sdk_flutter` + our server `/confirm`).

### 3. The backend is the single source of truth for entitlements

Credits and subscription state live server-side. Toss confirm/webhooks and
RevenueCat webhooks both write there. **The app reads entitlements; it never
trusts a client success callback.** This keeps the free-tier quota
un-bypassable and makes the gateway genuinely swappable.

### 4. Free-tier gating is entitlement-driven, not gateway-driven

"First N stories free" is enforced by the backend counting generations against
the account, independent of any payment provider. Payment merely grants an
entitlement (`pro_monthly` or `credits_N`) that lifts the quota.

## Rules that keep it swappable

- No `paymentKey` / `billingKey` / `receipt` / `confirm` above the interface.
- The app depends only on `PaymentGateway` + `activeEntitlements()`.
- A `FakePaymentGateway` (grants entitlements locally) backs development and
  widget tests so the paywall UI is built and tested before any real provider.
- The paywall *presentation* can be a WebView experiment surface (ADR 0003)
  even while the *transaction* goes through native IAP — separate concerns.

## User decision — RESOLVED (D1, 2026-07-11)

**iOS monetization model: credit packs only** (no subscription), Apple IAP
consumable via RevenueCat. The app offers a single **10-stories / ₩4,900**
pack. The `subscribe`/`pro_monthly` seam stays in the interface so the decision
is cheap to revisit, but it is not surfaced in the paywall. Toss remains the
web/Android gateway, not iOS.

Server-side quota (ADR 0002 core) is now implemented in `backend/` (free tier +
consumable credits, per-device, authoritative). Real IAP purchase → server
credit grant runs via a verified StoreKit/RevenueCat webhook (Phase 5 M3); the
backend's `POST /v1/credits` is the dev stub for that path.

### Durable, crash-safe quota (2026-07-14)

The authoritative store is now **durable and crash-safe** (`backend/quota.go`,
`quota_sqlite.go`): a **reserve → commit/release** ledger (a pending hold is
placed before generating, committed only once the story is delivered, released
on failure; an abandoned hold auto-expires via TTL so it is never a permanent
charge), **idempotent** credit grants keyed on the purchase id, and a pure-Go
SQLite backend selected fail-closed via `PLAYZY_QUOTA_STORE`. Everything sits
behind one `QuotaStore` interface, so Postgres (horizontal scale, D5) is a drop-in.

This is the **persistence foundation for accounts**: today entitlements key on the
client-selected `X-Device-Id` (durable *per-device* accounting, resettable by
rotating the id). The **next WU adds social login** (Apple — mandatory under
Guideline 4.8 once any third-party login is offered — plus Google + Kakao; no
email/password), keying entitlements to a verified identity and migrating a
device's quota/credits to the account on link. Login stays **optional/anonymous-
first** (Guideline 5.1.1(v) forbids forcing account creation for core features).

## Consequences

- We don't fight Apple; iOS ships approvably.
- Toss work isn't wasted — it's the correct web/Android gateway and the
  interface is ready for it.
- Slightly more upfront structure (interface + fake + backend entitlements) than
  a single hardcoded SDK, justified by swappability the user explicitly asked
  for.
