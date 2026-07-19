# Prod migration: SQLite-on-PVC → Postgres on db01 (k3s / ArgoCD)

**Status:** prepared for review — NOT applied. The k8s manifests live in the private
GitOps repo `marshallku/manifest` under `kubernetes/service/playzy/`; ArgoCD auto-syncs it,
so **pushing there deploys to prod**. This doc records the db01 provisioning (done) and points
at the finished manifest bundle (`manifest-changes/APPLY.md`) for the cutover. The app side is
already shipped: `PLAYZY_QUOTA_STORE=postgres` + `PLAYZY_DATABASE_URL` (backend commit `a919451`).

Topology chosen: **db01 Postgres** (own `playzy` DB + schema) with **Infisical** secrets (the
maji/irang pattern), prepare-for-review.

---

## 1. Provision the database on db01 — ✅ DONE (2026-07-19)

The `playzy` **database** and `playzy` **schema** were created on the db01 Postgres
(`192.168.219.130:5432`, the shared instance whose other services live in the `sssup`
database) using the existing shared DB user — no new role. The real backend migration was
run into the schema (the exact `pgMigrate`), so all tables already exist:

```
database: playzy   schema: playzy   schema_version: 3
tables: account, account_doc, auth_nonce, credit_grant, identity,
        quota, reservation, schema_version
```

Idempotent — the backend re-runs `pgMigrate` at every startup and no-ops when up to date.

**Connection URL for the manifest secret** (`PLAYZY_DATABASE_URL`) — fill the user/password
from your `.env` (`DATABASE_USER_NAME` / `DATABASE_USER_PASSWORD`); host/port/db/schema are
fixed:

```
postgres://<DATABASE_USER_NAME>:<DATABASE_USER_PASSWORD>@192.168.219.130:5432/playzy?sslmode=disable&search_path=playzy
```

The `search_path=playzy` is what scopes the backend to the `playzy` schema (pgx applies it on
every pooled connection). Switch `sslmode=disable` → `require` if db01 later terminates TLS.

---

## 2. Manifest cutover (Postgres store + Infisical secret)

The exact, finished manifest files live in **`manifest-changes/`** (`APPLY.md` + the four
files). Secrets use **Infisical** (the `playzy-prd` project), mirroring irang — the app
secret is no longer a SealedSecret. Apply that bundle into `marshallku/manifest`
`kubernetes/service/playzy/`:

- **ADD** `infisical-secret.yaml`, `infisical-credentials.yaml.example`
- **REPLACE** `api/deployment.yaml` (store → Postgres; SQLite volume/PVC + dev01 pin removed;
  `Recreate` → `RollingUpdate`; image tag stays CI-managed), `README.md`
- **DELETE** `pvc.yaml`, `secret.yaml.example` (and any committed `sealed-secret.yaml`)

Put the app secrets in Infisical `playzy-prd` (env `prd`, path `/`): `KAGI_SESSION` (the
`kagi_session` cookie — no account email/password), `PLAYZY_ADMIN_TOKEN`, and
`PLAYZY_DATABASE_URL` (the URL from §1). See `manifest-changes/APPLY.md` for the full step list. Keep `api/service.yaml` (NodePort 30511)
as-is — the Cloudflare tunnel targets it.

> ⚠️ There is **no automatic data migration** from the SQLite ledger to Postgres. At current
> scale the quota/credit ledger is small; the authoritative source is the RevenueCat purchase
> history (credits can be re-granted idempotently by purchase id). If any live credits exist,
> reconcile them before cutover, or grant a one-time bridge via `POST /v1/credits`. Confirm
> this is acceptable before applying.

---

## 3. Verify (after ArgoCD syncs)

- `kubectl -n playzy rollout status deploy/playzy-api`.
- `kubectl -n playzy logs deploy/playzy-api -c api` → shows `quota store: postgres`, no
  migration errors.
- `curl https://api-playzy.marshallku.dev/healthz` → `ok`.
- `curl https://api-playzy.marshallku.dev/v1/quota -H 'X-Device-Id: smoke-test'` → a fresh
  free-tier allowance (proves the store round-trips).
- On db01: `\dt playzy.*` in the `playzy` database shows `quota`, `reservation`,
  `credit_grant`, `account`, `identity`, `auth_nonce`, `account_doc`, `schema_version`.

---

## Rollback

Revert the manifest commit (ArgoCD re-syncs). The old SQLite PV used `Retain`, so if the
pre-cutover `pvc.yaml` is restored the previous ledger on dev01 is still intact (unless you
deleted it). The `playzy` Postgres schema is independent and can stay.
