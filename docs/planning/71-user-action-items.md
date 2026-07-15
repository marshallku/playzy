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
- [ ] **Install CocoaPods on the build machine** (`brew install cocoapods`) — now
      REQUIRED to run the app on the iOS sim at all. Two CocoaPods-only plugins
      (`purchases_flutter`, `flutter_secure_storage`) are present, so without
      `pod install` `flutter run`/launch fails ("CocoaPods not installed"). The Dart
      code compiles clean and the full unit suite passes; only the native
      link/on-device run is blocked. iOS min target is 13.0 in `app/ios/Podfile`.

## 🔴 Blocking — needed before auth can go live
Decision (2026-07-15): v1 supports **Apple + Kakao + Google** login. All three verify
via OIDC id_token; I need each provider's **client id (audience)** to validate tokens.

> **App status:** the login + account UI shell is DONE (commit `9600baf`) — login screen
> (3 provider buttons → tested AuthController), account screen (logout / delete-account),
> home entry, all widget-tested. What's still blocked is the **native credential fetch**
> behind the `SocialSignIn` seam (real per-provider SDKs) — needs the client ids below,
> iOS native config (Info.plist / entitlements / URL schemes), AND **CocoaPods installed**
> on the build machine (`brew install cocoapods` — currently missing, so pod-based plugins
> can't build). The **mandatory paywall login-gate** ("login-then-purchase") is intentionally
> NOT enabled yet: turning it on before native login works would break anonymous purchase.

- [ ] **Sign in with Apple** capability enabled for the app id; give me the **Services
      ID / client id** (audience). (Backend verifies Apple's id_token against Apple's
      JWKS — no .p8 needed for id_token verification; the .p8 Services key is only
      needed if we later do the auth-code→token exchange.)
- [ ] **Google** OAuth client (iOS + optionally Web) → give me the **client id(s)**
      (audience) the app will present. Verified against Google's JWKS.
- [ ] **Kakao** developer app with **OpenID Connect activated** → give me the
      **REST API key / app key** (Kakao id_token audience). Verified against
      `https://kauth.kakao.com/.well-known/jwks.json`.
- [ ] App **session-signing secret** (I can generate one; you store it in prod
      secrets as `PLAYZY_SESSION_SECRET`).

## 🔴 Blocking — production infrastructure
- [x] **Official AI provider to replace kagi — CODE DONE.** The official Anthropic
      Messages-API provider is wired behind the `callAI` seam (`PLAYZY_AI_PROVIDER=anthropic`).
      **What's left for YOU:**
      - [ ] Provide an **`ANTHROPIC_API_KEY`** (set it in the host's secrets). Startup
            fails closed without it when the provider is `anthropic`, so nothing ships half-configured.
      - [ ] **Approve the per-story token cost.** Default model is `claude-opus-4-8`
            (override with `ANTHROPIC_MODEL`; a cheaper model like `claude-haiku-4-5` is a
            one-env-var change if you want a lower per-story cost). A bedtime story is a few
            short pages, so cost/story is small — but confirm before launch.
      - [ ] **Live smoke test** — once the key is set, generate one real story end-to-end
            (only step that couldn't be pre-verified without a key; unit tests already cover
            request-shaping + parsing against a mock).
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

## 🔵 Hardening (WU7 / fast-follow) — not blocking v1
- [ ] **Account-deletion recreation window (deletion-integrity).** After `DELETE /v1/me`,
      a request that started *entirely before* deletion completed can recreate a
      subject-keyed quota/credit row (quota is keyed by opaque subject with no FK to
      account, since anonymous device subjects have none — so no store can refuse it; all
      three stores — memory/sqlite/postgres — share this). The authed generate path is
      narrowed by `requireAccount` revalidating every request (deleted account → 401), but
      the **admin/RevenueCat webhook `AddCredits` path has no account-existence check**, so
      a purchase settling for a just-deleted account can mint a ghost credit. **Fix (one
      place, all stores):** add an account-existence guard in the credit-grant handler for
      account-scoped subjects (or a `deleted_account` tombstone). Small, code-only; decide
      whether to fold into launch or fast-follow. Surfaced by codex during the Postgres
      store review; deliberately kept out of the store-port unit to avoid divergence.
- [ ] **Device attestation (App Attest / DeviceCheck on iOS, Play Integrity on
      Android).** The iOS-correct way to prove a request comes from a genuine,
      unmodified app instance on a real device (mTLS is the wrong tool — an embedded
      client cert is extractable). Binds `X-Device-Id` to a Secure Enclave key so it
      can't be spoofed. Real value at launch scale = **preventing free-tier / LLM-cost
      abuse** (bots farming free stories with random device ids), and it would also
      unblock a safe anonymous-purchase→account credit claim. Cost: no simulator
      support, server-side attestation verification in Go (no official SDK), dev
      bypass needed. Decide priority: fold into WU7, or a post-launch fast-follow.
- [ ] App icon + mascot/brand character (D3/D4 — needs an illustrator).
- [ ] Brand hue finalization (D4, currently periwinkle #5265C6 provisional).
- [ ] Onboarding hero art / illustration style bible.
- [ ] App Store screenshots + marketing copy.
- [ ] Font glyph subsetting to cut app size (D9) — optimization, not a blocker.

## 🟢 Decisions — RESOLVED 2026-07-15
- [x] **Login providers for v1**: **Apple + Kakao + Google** (all three).
- [x] **Profile sync (WU6)**: **account-synced from launch** (WU6 in scope).
- [x] **Anonymous use**: **anonymous-first** — 3 free stories before login.
- [x] **Anonymous quota merge & device authenticity** (security decision): the app's
      `X-Device-Id` is a client-generated per-install value (stored in
      shared_preferences → lost on reinstall) and is NOT an authenticated credential,
      so it can't safely gate a credit transfer. Decision: **login-before-purchase** —
      the paywall requires sign-in (WU5), so purchased credits are account-scoped from
      the moment of purchase (RevenueCat `logIn(accountId)`); there are no anonymous
      credits to steal or strand. The anonymous **free tier is NOT merged** on login —
      a logged-in user simply gets the account's own allowance. Robust free-tier
      enforcement needs device attestation (the tier is already soft: reinstall = a
      new device id), so no fragile merge machinery is built; attestation is a WU7
      hardening item. Account subjects (`acct_…`) and device subjects are namespace-
      separated so a client can't present an account-shaped device id. An
      anonymous-purchase→login "claim" flow (needing device-ownership proof) is
      **deferred**. → See WU7 hardening below.

---

### How this list is maintained
I update this file as new blockers surface during implementation and check items off
as you resolve them. Anything I code around (stubs, seams, `--dart-define` slots) is
noted next to its item so you know exactly what value to hand back.
</content>
