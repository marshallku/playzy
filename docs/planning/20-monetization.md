# Monetization

> Evidence: `research/ai-story-generator-competitor-analysis.md`. Decision
> record: ADR 0002. Open items: D1 (model & price), D2 (free limit).

## Model

**Freemium.** A few stories free, then pay. Confirmed as the market-standard
shape.

### Free tier

- **3 stories, lifetime** (D2). Market standard is lifetime 2–5 (mode = 3), or
  monthly 3. Lifetime-3 is the simplest to communicate and enforce.
- Enforced **server-side** by generation count against the account — cannot be
  bypassed by reinstalling if tied to sign-in; anonymous device accounts get a
  provisional quota that converts on sign-in.

### Paid tier — credit packs only (D1 resolved 2026-07-11)

**No subscription.** After the free tier, users buy **consumable credit packs**
via Apple IAP:

- **Credit pack (consumable IAP):** 10 stories per pack. Provisional price:
  **₩4,900 / 10 stories** — tune with data.

The `PaymentGateway` interface still supports subscriptions (the `subscribe`
method + the `pro_monthly` entitlement seam remain) so the decision is cheap to
revisit, but the app offers only credit packs.

### iOS payment path

**Apple IAP via RevenueCat** (not Toss — see ADR 0002 / `research/payments.md`
for why Toss is a non-starter on iOS for digital goods). Toss is wired as the
**web/Android** gateway behind the same interface.

## Where value is added later (upsell ladder)

The competitor gap analysis points the roadmap:

1. **Illustrations** per story (D3) — first premium unlock.
2. **Audio narration**, then **parent voice** narration (strong differentiator
   for 0–6 / bedtime).
3. **Developmental tuning** depth (age-band-specific pedagogy).
4. Character consistency, printable keepsake books.

## Pricing presentation

Lives on a **WebView experiment surface** (ADR 0003 Tier B) so copy, ordering,
and A/B tests ship without an app release — while the transaction itself stays
native IAP. The paywall reads entitlements from the backend, never trusts a
client callback.

## Guardrail

Never let a payment failure or backend hiccup strand a parent mid-bedtime. If
entitlement can't be verified, fail *open* for an already-started story and
reconcile later; fail *closed* only at the point of starting a new generation
beyond quota.
