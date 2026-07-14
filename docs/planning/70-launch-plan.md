# Launch plan — auth + accounts + payments → shippable

Goal: take Playzy from "playable on a dev backend, per-device quota, dev-stub
payments" to a **launchable iOS app**: real Apple IAP credits, real user accounts,
account-scoped entitlements, production provider + hosting.

Driven as an autonomous loop; each work-unit follows the full gate
(plan → codex plan review → implement → unit test → e2e if applicable →
codex cross-review → `~/save.sh`). Items needing the user live in
[`71-user-action-items.md`](./71-user-action-items.md).

## Decisions locked
- **Payments provider = RevenueCat** (ADR 0002; validated by market research
  2026-07-15: ~1/3 of new subscription apps launch on it, first-class Flutter SDK,
  webhook auth is a simple shared-secret header — trivial in our Go backend, whereas
  Apple's official App Store Server Library has **no Go** version). Credit packs are
  **consumables** granted server-side via the `NON_RENEWING_PURCHASE` webhook,
  idempotent on `transaction_id` — the documented standard pattern.
- **Primary auth = Sign in with Apple** (Apple mandates it on iOS when any social
  login is offered; the identity token is a JWS verifiable in Go against Apple's
  JWKS). Kakao / Google added behind the same account seam as fast-follows (Kakao is
  the common KR default).
- **Subject model**: every entitlement is keyed on an opaque **subject** =
  `deviceId` while anonymous, `accountId` after login. RevenueCat `appUserID` is set
  to that same subject, so a purchase always credits the right holder and the webhook
  needs no separate device map. On first login the anonymous device subject is
  **merged** into the account (idempotent link record).

## Work-units (see task tracker for live status)
1. **WU1 — Backend RevenueCat webhook.** `POST /v1/webhooks/revenuecat`: verify
   shared-secret auth, parse event, product→credits allowlist, idempotent grant on
   `transaction_id`, ack 200 on every handled case (RC retries on non-2xx). Fully
   buildable + unit-testable now (no Apple/RC account). Keeps the dev-stub
   `/v1/credits` admin path for local e2e.
2. **WU2 — App ApplePaymentGateway + paywall.** `purchases_flutter`, platform-
   conditional gateway, paywall polls `/v1/quota` after purchase in real-RC mode.
   Compiles + unit-tests now; live purchase gated on RC key + App Store Connect product.
3. **WU3 — Backend auth foundation.** Account model, `POST /v1/auth/apple`
   (verify Apple identity token JWS via cached JWKS → upsert account → issue app
   session JWT), `Authorization: Bearer` middleware, `GET /v1/me`, account-deletion
   scaffold. Unit-testable with a stubbed JWKS.
4. **WU4 — Account-scoped entitlements + device→account migration.** Resolve subject
   = account (authed) or device (anon); merge device quota into account on first login
   (idempotent); RC appUserID alias device→account.
5. **WU5 — App auth UI + session wiring.** Sign in with Apple button, secure token
   storage, Bearer on all clients, account screen (sign out / delete). Anonymous path
   still works offline.
6. **WU6 — Profile sync to account** (multi-device). Optional for launch; decide at
   the WU whether single-device local profiles are acceptable for v1.
7. **WU7 — Launch hardening.** Replace **kagi (dev-only)** with an official AI
   provider behind `callAI`; prod quota store + hosting (D5); privacy policy + ToS +
   in-app account deletion; App Store metadata; final content-safety pass. Most of
   this is user/designer/legal-gated — tracked in the user-action doc.

## Sequencing notes
- WU1→WU2 ship payments **device-scoped** first (forward-compatible via the subject
  model), so payments don't block on auth.
- WU3 unblocks WU4/WU5/WU6.
- WU7 is the external-blocker bucket; its code seams (provider swap, deletion
  endpoint) are built as they come up, but going live needs the user-action items.

## Hard launch blockers that are NOT code (must be resolved by the user)
See [`71-user-action-items.md`](./71-user-action-items.md). The big ones: Apple
Developer Program + App Store Connect product, RevenueCat account/key, an **official
AI provider** to replace kagi (kagi is unofficial/dev-only — cannot ship), production
hosting, and legal docs.
</content>
</invoke>
