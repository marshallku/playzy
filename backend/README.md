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
  **Dev stub:** in production this is driven by a *verified* StoreKit/RevenueCat
  purchase webhook, never called by the client directly.
- `GET /v1/catalog/situations` — the SDUI document for the situation picker
  (ADR 0003), matching the app's bundled default.
- `GET /healthz` — `ok`.

## Quota (ADR 0002)

The backend is the **authoritative** enforcer: per `X-Device-Id`, a free tier
(3 stories) then consumable credits (credit-packs-only, D1 — no subscription).
Generation reserves quota **before** calling the AI and refunds on failure, so a
failed story is never charged and the limit can't be bypassed client-side. The
app's local counters are only an offline mirror. `InMemoryQuotaStore` is
dev-only — production must back it with a shared store (Redis/DB) so quota
survives restarts and scales horizontally.

## Run (local dev)

```bash
# 1) Start kagi's HTTP server (handles Kagi auth/keyring — see ../../kagi).
#    Needs your Kagi credentials (KAGI_EMAIL/KAGI_PASSWORD or KAGI_SESSION).
kagi serve -addr 127.0.0.1:8921 &

# 2) Start the Playzy backend (defaults shown).
KAGI_SERVE_URL=http://127.0.0.1:8921 PLAYZY_ADDR=:8080 go run .

# 3) Point the app at it. The app then reads the authoritative quota from
#    GET /v1/quota, sends X-Device-Id, and shows the paywall on 402.
cd ../app
flutter run --dart-define=PLAYZY_API_BASE_URL=http://localhost:8080

# To also exercise the PAID flow end-to-end against the local backend, run the
# backend with an admin token and give the app the same token so the paywall can
# grant server credits (dev only — in prod a verified purchase webhook does this):
#   PLAYZY_ADMIN_TOKEN=devsecret KAGI_SERVE_URL=... go run .
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

## Swapping the AI provider

kagi is a **reverse-engineered, unofficial** client and is dev-only (ADR 0001).
To move to OpenAI/Anthropic/etc., change **only** `callAI` in `main.go` — the
prompt builder, parser, contract, and the entire app stay untouched.

## Test

```bash
go test ./...   # prompt/parse/catalog + handler tests (mock kagi, no creds)
```

## Notes / follow-ups

- Free-tier quota + entitlements must be enforced **here** in production (ADR
  0002), not just mirrored in the app. Not yet implemented — the app's local
  gating is a stand-in.
- Content-safety: guardrails live in the prompt (`prompt.go`); a real launch
  should add an output moderation pass before returning a story to a child.
- Hosting is undecided (D5); kagi is a local dev dependency only.
