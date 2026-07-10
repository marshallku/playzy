# Research — Payments (Toss Payments vs Apple IAP) for iOS-first launch

> Gathered 2026-07-11. Inputs to ADR 0002. Bottom line drives a **user
> decision** tracked in `planning/90-open-decisions.md`.

## TL;DR

For a **digital** story-generation subscription launching on **iOS**, **Apple
In-App Purchase (StoreKit) is effectively mandatory**, and **Toss Payments is
not a realistic path for the in-app flow**. Two hard blockers:

1. **App Store Guideline 3.1.1** — digital content/subscriptions consumed
   in-app require Apple IAP. External PGs (Toss, Stripe) → rejection.
2. **Korea's external-payment entitlement doesn't rescue Toss on Flutter.**
   Apple's Korean implementation still charges **26%**, **requires a native
   payment UI and explicitly forbids WebView**, is **KR-store-only**, and
   **can't coexist with IAP** in one binary. The official
   `tosspayments_widget_sdk_flutter` SDK is **WebView-based**, so it violates
   the entitlement's native-UI rule.

**Recommendation:** iOS ships with **Apple IAP via RevenueCat**, behind a
`PaymentGateway` abstraction. **Toss** is reserved for **web/Android**, where
it's first-class and low-fee (~2–3%).

## When is Toss allowed on iOS?

| Selling this | On iOS you must use |
| --- | --- |
| Digital goods consumed in-app (AI stories, credits, subscriptions) | **Apple IAP** (3.1.1). Toss → rejection. |
| Physical goods / real-world services | External PG required — Toss is correct here |
| Reader apps, p2p, etc. | Special cases — not our product |

Playzy (free stories → pay for more) is **digital content consumed in-app** →
IAP-mandatory.

## Korea's in-app payment law — why it still doesn't help

Korea's 전기통신사업법 amendment forced Apple to allow third-party PGs via the
**StoreKit External Purchase Entitlement (South Korea)**. Reality:

- **26% commission** (only ~3–4% less than standard 30%), **plus** Toss's ~2–3%
  PG fee → worse economics than plain IAP.
- **KR storefront only**, submitted as a **separate binary**; can't mix with IAP.
- **Native UI required, WebView explicitly forbidden** — the dealbreaker for the
  WebView-based Toss Flutter SDK.
- Heavy compliance: mandatory external-purchase modal, monthly sales reports to
  Apple (≤15 days), payment to Apple (≤45 days), audit rights, loss of
  Ask-to-Buy / Family Sharing / Apple-assisted refunds.

**Verdict:** for a Flutter app the entitlement buys nothing. Standard IAP wins.

## iOS recommendation — Apple IAP via RevenueCat

- **RevenueCat (`purchases_flutter`)** over raw `in_app_purchase`: handles
  server-side receipt validation, entitlement sync, **restore purchases**
  (required by 3.1.1), webhooks, paywalls. Raw package only drives the native
  sheet — you'd hand-roll validation.
- Both monetization models map cleanly: **credit pack → consumable IAP**;
  **subscription → auto-renewable subscription IAP**. RevenueCat "entitlements"
  model both.
- Keep **Toss for web + Android** (Korea): full widget/billing, ~2–3% fees, no
  Apple tax.

## Toss Payments technical reference (web/Android/abstracted path)

- **SDK:** `tosspayments_widget_sdk_flutter` (pub.dev v2.2.0, MIT, WebView-based;
  `PaymentWidget` / `PaymentMethodWidget` / `AgreementWidget`). Flow:
  `renderPaymentMethods(amount)` → `renderAgreement()` →
  `requestPayment(orderId, orderName)`.
- **Server confirm (승인) is mandatory & server-side.** After the widget returns
  `paymentKey/orderId/amount`, validate `amount` against the stored order, then:
  ```
  POST https://api.tosspayments.com/v1/payments/confirm
  Authorization: Basic base64("{SECRET_KEY}:")
  { "paymentKey": "...", "orderId": "...", "amount": 12900 }
  ```
  Confirm within the 10-min window. **Only a successful confirm captures money**
  — the widget success callback alone does not.
- **Billing / 정기결제:** issue a **billingKey** (`/v1/billing/authorizations/issue`),
  store it server-side mapped to `customerKey`, charge each cycle
  (`/v1/billing/{billingKey}`). **No scheduler provided** — you build the cron.
  Requires a **risk review + separate contract** with Toss.
- **Test keys:** `test_ck_` (client), `test_sk_` (secret), `test_gck_` (widget).
- **Server-only:** secret key, `/confirm`, amount validation, billingKey storage,
  webhooks, scheduler. **Client:** clientKey, `requestPayment()`, method/agreement UI.

## Server vs client split (both gateways)

The **backend is the single source of truth for entitlements** (credits /
subscription state). Toss confirm + webhooks write to it; RevenueCat webhooks
write to it. The app **reads entitlements, never trusts a client success
callback**.

## Sources

- Apple — third-party payment provider in South Korea:
  https://developer.apple.com/support/storekit-external-entitlement-kr/
- Apple — apps distributed in South Korea:
  https://developer.apple.com/news/?id=q0feipe4
- Guideline 3.1 / IAP: https://iossubmissionguide.com/guideline-3-1-in-app-purchase/
- Toss Flutter SDK: https://pub.dev/packages/tosspayments_widget_sdk_flutter
- Toss payment flow v2: https://docs.tosspayments.com/guides/v2/get-started/payment-flow
- Toss API reference: https://docs.tosspayments.com/reference
- Toss billing API: https://docs.tosspayments.com/guides/v2/billing/integration-api
- RevenueCat Flutter: https://www.revenuecat.com/docs/getting-started/installation/flutter
