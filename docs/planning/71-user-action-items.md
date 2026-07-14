# ⚠️ User action items — things only you (Marshall) can do

Living checklist of everything that **blocks a real launch but cannot be done in
code**: external accounts, API keys, paid memberships, legal content, designer
assets, and decisions. I build every code seam so that dropping these in requires
no further engineering. Check items off as you complete them; tell me the values
(or where to read them) and I wire them up.

Last updated: 2026-07-15.

## 🔴 Blocking — needed before payments can go live
- [ ] **Apple Developer Program** membership ($99/yr) — required for App Store
      Connect, Sign in with Apple, and a real IAP product.
- [ ] **App Store Connect app record** for Playzy (bundle id, app name).
- [ ] **Consumable IAP product** `credits_10` in App Store Connect
      (10 stories, provisional ₩4,900). Confirm final price/pack size (decision D1/D2).
- [ ] **RevenueCat account** (free under $2.5k/mo tracked revenue) →
      - [ ] iOS **public SDK API key** → give me for `--dart-define=PLAYZY_REVENUECAT_IOS_KEY=appl_...`
            (wired in WU2; the app uses the real Apple gateway only when this + a
            backend URL are both set).
      - [ ] connect App Store Connect (App-Specific Shared Secret / In-App Purchase key)
      - [ ] map product `credits_10` in RevenueCat
      - [ ] configure the **webhook** → our `POST /v1/webhooks/revenuecat`, set the
            Authorization header secret → give me for `REVENUECAT_WEBHOOK_AUTH`
            (also set `REVENUECAT_APP_ID` for project isolation).
- [ ] Enable the **In-App Purchase capability** on the app target in Xcode /
      App Store Connect (RevenueCat requires it; a simulator build does NOT catch a
      missing capability).
- [ ] **Sandbox tester** account (App Store Connect → Users) to exercise a real
      purchase before TestFlight.
- [ ] **Install CocoaPods on the build machine** (`brew install cocoapods`). It is
      currently NOT installed, so `purchases_flutter` (a CocoaPods-only plugin) is
      not natively linked — the app still builds/runs in fake mode, but the real
      RevenueCat path needs `pod install` to work. iOS min target is set to 13.0
      (RevenueCat requirement) in `app/ios/Podfile`.

## 🔴 Blocking — needed before auth can go live
- [ ] **Sign in with Apple** capability enabled for the app id + a **Services key**
      (Key ID / Team ID / private key .p8) → give me for backend token verification.
- [ ] App **session-signing secret** (I can generate one; you store it in prod secrets).
- [ ] (Optional, KR) **Kakao** developer app (REST API key, redirect) if we add Kakao login.
- [ ] (Optional) **Google** OAuth client if we add Google login.

## 🔴 Blocking — production infrastructure
- [ ] **Official AI provider to replace kagi.** kagi is unofficial/dev-only and
      **cannot ship**. Pick Anthropic or OpenAI (behind the existing `callAI` seam),
      provide an **API key**, and approve the per-story token cost. (This is the single
      biggest non-obvious launch blocker.)
- [ ] **Backend hosting decision (D5)** — pick a host (Fly / Railway / Cloud Run /
      etc.). Then I wire the existing deploy workflow + secrets.
- [ ] **Production quota store** — sqlite-on-persistent-disk is fine for v1 single
      instance; Postgres when scaling horizontally. Confirm the v1 choice.
- [ ] **Secrets management** in the chosen host (RC webhook secret, Apple keys,
      session secret, AI provider key, DB path/URL).

## 🟠 Blocking — legal / store review
- [ ] **Privacy Policy** URL (required; kids category has stricter rules — 0–6 audience).
- [ ] **Terms of Service** URL.
- [ ] **App Privacy** questionnaire in App Store Connect (data types collected).
- [ ] Confirm **children's-privacy** posture (COPPA/GDPR-K) — since the audience is
      toddlers, parents are the account holders; no data from children directly.
      May need legal review.

## 🟡 Needed for a polished launch (designer / content)
- [ ] App icon + mascot/brand character (D3/D4 — needs an illustrator).
- [ ] Brand hue finalization (D4, currently periwinkle #5265C6 provisional).
- [ ] Onboarding hero art / illustration style bible.
- [ ] App Store screenshots + marketing copy.
- [ ] Font glyph subsetting to cut app size (D9) — optimization, not a blocker.

## 🟢 Decisions I need from you (cheap to answer, unblocks a WU)
- [ ] **Login providers for v1**: Apple only, or Apple + Kakao (+ Google)?
- [ ] **Profile sync (WU6)**: is single-device (local) acceptable for v1, or do you
      want account-synced profiles across devices at launch?
- [ ] **Anonymous use**: keep letting users generate the 3 free stories *before*
      login (recommended — lower funnel friction), or require login up front?

---

### How this list is maintained
I update this file as new blockers surface during implementation and check items off
as you resolve them. Anything I code around (stubs, seams, `--dart-define` slots) is
noted next to its item so you know exactly what value to hand back.
</content>
