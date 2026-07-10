# Roadmap

Sequenced to ship the **wedge** (0–6, situation-solving, bedtime) fast, with
the swappable seams in place from day one. Each milestone follows the workflow:
plan → implement → test → review.

## M0 — Foundations (this phase)

- [x] Service / design / payments research (`docs/research/`)
- [x] Planning + architecture ADRs (`docs/`)
- [x] Design system (`DESIGN.md`)
- [x] Flutter project scaffold + design tokens + theme
- [x] Domain models (`ChildProfile`, `Situation`, `Story`)
- [x] Interfaces + fakes: `StoryApi`/`FakeStoryApi`, `PaymentGateway`/`Fake`

## M1 — Playable UI on fakes (no real backend)

- [ ] Onboarding
- [ ] Child profile create/edit (native, local persistence)
- [ ] Situation picker via **SDUI renderer** (bundled default catalog)
- [ ] Story generation flow + loading delight (against `FakeStoryApi`)
- [ ] Story reader (night mode, font slider, page-turn) — the payoff screen
- [ ] Free-tier gating + paywall UI (against `FakePaymentGateway`)
- [ ] Widget tests for each core flow

Exit: the entire experience is demoable and tested offline.

## M2 — Real AI backend

- [x] Playzy backend (AI gateway) wrapping `kagi serve` (`backend/`, Go)
- [x] `HttpStoryApi` + `HttpCatalogApi` in the app target the stable contract
- [x] Prompt engineering + age-band guardrails; structured story output
- [x] SDUI catalog served from backend
- [ ] Server-side generation quota (free-tier enforcement) — app gating is a
      stand-in until this lands
- [ ] End-to-end run verified with real Kagi credentials (needs user creds)

Exit: real personalized stories end-to-end on a dev backend (pending creds).

## M3 — Monetization (gated on D1)

- [ ] Confirm model & price (D1)
- [ ] `ApplePaymentGateway` (RevenueCat) — consumable + subscription
- [ ] Backend entitlements + RevenueCat webhooks
- [ ] Paywall as WebView experiment surface

Exit: a user can pay and lift the quota on a TestFlight build.

## M4 — Launch hardening (iOS)

- [ ] Accessibility & night-reading polish pass
- [ ] Content-safety review of prompts/outputs (critical for young children)
- [ ] App Store assets (needs designer — see ⚠️ flags), privacy, review submission
- [ ] Production backend hosting (D5)

## Fast-follows (post-launch)

Illustrations (D3) → audio narration → parent voice → Android/web with Toss
gateway → character consistency / print.

## Deferred / needs-designer (not blocking)

Mascot, illustration style bible, final tonal ramps + brand hue, custom icons,
app icon, hero art — isolated behind tokens/asset slots (`DESIGN.md` §6, §11).
