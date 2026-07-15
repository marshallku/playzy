# Playzy backend

The AI gateway between the Flutter app and the AI provider (ADR 0001). The app
speaks a stable, provider-agnostic contract; this service owns the prompt and
the provider. Today it is the thinnest viable adapter: it proxies to a local
[`kagi serve`](../../kagi) and shapes the result into a `Story`.

## Contract (what the app depends on)

- `POST /v1/stories` — header `X-Device-Id` (required); body `StoryRequest`
  (`childName`, `ageBand`, `situationIds`, `topic?`, `interests?`, `characters?`,
  `mood?`, `length?`) → 
  `Story` (`id`, `title`, `pages[]`, `createdAt`). Enforces the quota: `402` when
  free stories are used up and no credits remain.
- `GET /v1/quota` — header `X-Device-Id` → `{freeUsed, freeLimit, credits,
  canGenerate}`. The authoritative allowance (ADR 0002).
- `POST /v1/credits` — header `X-Device-Id`, body `{amount}` → grants credits.
  **Dev stub:** admin-token-gated path used for local testing. Kept alongside the
  real webhook below until the live purchase path is exercised on TestFlight.
- `POST /v1/webhooks/revenuecat` — the **production purchase path**. RevenueCat
  delivers a shared-secret-authenticated event when a consumable credit pack is
  bought; the handler grants credits idempotently on the store `transaction_id`.
  Disabled (404) when `REVENUECAT_WEBHOOK_AUTH` is unset. Grants only
  `NON_RENEWING_PURCHASE` events for a mapped product, bound to the configured app +
  `PRODUCTION` environment; every other handled case is acked with 200 (RevenueCat
  retries any non-2xx). The event's `app_user_id` is the **subject** (device id now,
  account id after login). See ADR 0002.
- `GET /v1/catalog/situations` — the SDUI document for the situation picker
  (ADR 0003), matching the app's bundled default.
- `POST /v1/auth/nonce` → `{nonce}` — a single-use, short-lived login nonce. The
  client hashes it (sha256) into the provider authorization request and returns the
  raw value to the login endpoint (OIDC anti-replay). Disabled (404) without
  `PLAYZY_SESSION_SECRET`.
- `POST /v1/auth/apple` — body `{idToken, nonce}` → `{token, account:{id}, isNew}`.
  Verifies a Sign in with Apple id_token (RS256 against Apple's JWKS, iss/aud/exp),
  enforces the nonce binding, upserts the account, and returns an app session JWT.
  Disabled (404) without `PLAYZY_SESSION_SECRET` or `APPLE_CLIENT_ID`. Google/Kakao
  join via the same path (WU3b).
- `GET /v1/me` — header `Authorization: Bearer <session>` → `{id, createdAt}`.
- `DELETE /v1/me` — Bearer → `204`. Deletes the account (Apple-mandated) and, because
  the session's account is re-checked on every request, immediately invalidates all
  of its sessions.
- `GET /healthz` — `ok`.

**Subject scoping.** `POST /v1/stories` and `GET /v1/quota` resolve their quota
**subject** from the request: a valid `Authorization: Bearer <session>` scopes to the
**account** (`acct_…`); otherwise the anonymous `X-Device-Id` is used (and may not
use the reserved `acct_` prefix). A present-but-invalid Bearer is a 401 (no silent
fallback to device scope). Purchased credits are account-scoped from purchase time
(the app signs in before the paywall, so RevenueCat `appUserID` = the account); the
v1 free tier is device-scoped and NOT merged into the account on login (robust free-
tier enforcement needs device attestation — a WU7 hardening item). `DELETE /v1/me`
purges every row keyed by the account subject (quota, credit grants, reservations).

Sessions are stateless HS256 JWTs (30d) carrying the account id + a token version;
every authenticated request re-loads the account and checks the version, so a
deleted/rotated account can't keep using an old token. See ADR 0002 (accounts key
the durable quota subject once WU4 lands).

## Quota (ADR 0002)

The backend is the **authoritative** enforcer: per `X-Device-Id`, a free tier
(3 stories) then consumable credits (credit-packs-only, D1 — no subscription).
The app's local counters are only an offline mirror.

**Reserve → commit/release ledger.** A generation places a *pending hold* before
calling the AI and only **commits** it once the story is delivered; a failed or
abandoned generation is **released** (never charged), and concurrent in-flight
holds can't over-spend. A hold that is never committed (e.g. a crash) auto-expires
after a TTL, so it is never a permanent charge, and a *detected* delivery failure
releases the hold. A residual window remains — a successful response write does
not prove the client received the story (net/http may buffer; the connection can
drop) — so a rare buffered-but-undelivered story can be charged. It is bounded to
a single unit and is irreducible at this layer: exactly-once ("charged iff
delivered") needs request idempotency + a client-confirmed delivery step, which
arrives with server-side story persistence in a later WU. Credit grants are **idempotent** on a key (the verified
purchase id in production), so a redelivered purchase webhook grants once.

**Storage.** `memory` is dev-only (volatile). `sqlite` (`PLAYZY_QUOTA_STORE=sqlite`
+ `PLAYZY_DB_PATH`) is durable and crash-safe, pure-Go (no cgo). Both sit behind
one `QuotaStore` interface, so production swaps in Postgres (horizontal scale, a
D5/hosting decision) without touching handlers.

**Scope.** This is durable **per-device accounting**, not unbypassable
enforcement: `X-Device-Id` is client-selected and resettable until accounts
(Apple/Google/Kakao login) land in the next WU and key entitlements to a verified
identity.

## Run (local dev)

```bash
# 1) Start kagi's HTTP server (handles Kagi auth/keyring — see ../../kagi).
#    Needs your Kagi credentials (KAGI_EMAIL/KAGI_PASSWORD or KAGI_SESSION).
kagi serve -addr 127.0.0.1:8921 &

# 2) Start the Playzy backend. PLAYZY_QUOTA_STORE is REQUIRED (fail-closed, no
#    default): `memory` for dev (volatile) or `sqlite` for durable quota.
PLAYZY_QUOTA_STORE=memory KAGI_SERVE_URL=http://127.0.0.1:8921 PLAYZY_ADDR=:8080 go run .

# Durable quota that survives restarts (reserve→commit ledger in a SQLite file):
PLAYZY_QUOTA_STORE=sqlite PLAYZY_DB_PATH=./playzy.db KAGI_SERVE_URL=http://127.0.0.1:8921 go run .

# 3) Point the app at it. The app then reads the authoritative quota from
#    GET /v1/quota, sends X-Device-Id, and shows the paywall on 402.
cd ../app
flutter run --dart-define=PLAYZY_API_BASE_URL=http://localhost:8080

# To also exercise the PAID flow end-to-end against the local backend, run the
# backend with an admin token and give the app the same token so the paywall can
# grant server credits (dev only — in prod a verified purchase webhook does this):
#   PLAYZY_QUOTA_STORE=memory PLAYZY_ADMIN_TOKEN=devsecret KAGI_SERVE_URL=... go run .
#   flutter run --dart-define=PLAYZY_API_BASE_URL=http://localhost:8080 \
#               --dart-define=PLAYZY_DEV_ADMIN_TOKEN=devsecret
```

With no `PLAYZY_API_BASE_URL`, the app runs entirely on fakes (no backend
needed) — see `app/lib/core/env.dart`.

## Config

| Env | Default | Meaning |
| --- | --- | --- |
| `PLAYZY_ADDR` | `:8080` | Listen address |
| `KAGI_SERVE_URL` | `http://127.0.0.1:8921` | Where `kagi serve` is listening |
| `PLAYZY_QUOTA_STORE` | **required** | `memory` (dev, volatile) or `sqlite` (durable). No default — a missing/unknown value is fatal, so a prod deploy can't silently boot on the restart-volatile store. |
| `PLAYZY_DB_PATH` | — | SQLite file; **required** when `PLAYZY_QUOTA_STORE=sqlite`. |
| `PLAYZY_ADMIN_TOKEN` | — | Guards the dev-stub `POST /v1/credits`. Empty → endpoint disabled. |
| `REVENUECAT_WEBHOOK_AUTH` | — | Shared secret RevenueCat sends in the `Authorization` header of every webhook. Empty → `POST /v1/webhooks/revenuecat` disabled (404). |
| `REVENUECAT_APP_ID` | — | When set, only accepts webhook events for this RevenueCat app id (project isolation). |
| `REVENUECAT_ALLOW_SANDBOX` | — | `1` accepts `SANDBOX` purchase events (dev/testing only). Unset → production purchases only. |
| `PLAYZY_SESSION_SECRET` | — | HS256 key for app session JWTs. Empty → auth endpoints disabled (404). Must be ≥32 bytes (fails startup otherwise). |
| `APPLE_CLIENT_ID` | — | Sign in with Apple audience (Services ID / bundle id) the id_token must carry. Empty → `/v1/auth/apple` disabled (404). |

## Swapping the AI provider

kagi is a **reverse-engineered, unofficial** client and is dev-only (ADR 0001).
To move to OpenAI/Anthropic/etc., change **only** `callAI` in `main.go` — the
prompt builder, parser, contract, and the entire app stay untouched.

## Test

```bash
go test ./...   # prompt/parse/catalog + handler tests (mock kagi, no creds)
```

## Notes / follow-ups

- Free-tier quota + entitlements are enforced **here** (ADR 0002): authoritative
  reserve→commit ledger, durable via SQLite. Still to do for a real launch:
  account-scoped entitlements (so quota can't be reset by rotating `X-Device-Id`)
  and the Postgres backend for horizontal scale.
- Content-safety, defense in depth: (1) prompt guardrails (`prompt.go` + the
  system prompt), (2) a **deterministic output-moderation pass** (`moderation.go`)
  that runs a categorized, evasion-resistant (whitespace/zero-width-normalized)
  child-safety lexicon over the title + every page and **fail-safe** replaces the
  whole story with the gentle default on any hit (the tripped category is logged
  for tuning). The lexicon is severe + low-false-positive by design. A
  **model-based** classification pass (a second AI call) is a worthwhile future
  layer for nuance the lexicon can't capture.
- Hosting is undecided (D5); kagi is a local dev dependency only.
