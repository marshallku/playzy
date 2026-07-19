# Manifest changes for the Postgres + Infisical cutover (review bundle)

These are the finished manifest files for `marshallku/manifest`
`kubernetes/service/playzy/` — **prepared for review, not pushed** (pushing to that repo =
live ArgoCD deploy). Apply them in your own clone, then commit/push. Mirrors the irang
Infisical pattern; the db01 `playzy` database + schema are already provisioned + migrated
(see `../postgres-k3s-migration.md`).

## Apply into `kubernetes/service/playzy/`

| Action | File | Notes |
| --- | --- | --- |
| **ADD** | `infisical-secret.yaml` | InfisicalSecret CR → syncs `playzy-secret` from the `playzy-prd` project |
| **ADD** | `infisical-credentials.yaml.example` | universal-auth bootstrap template (apply once, manually) |
| **REPLACE** | `api/deployment.yaml` | store swapped to Postgres; SQLite volume/PVC + dev01 pin removed; `Recreate` → `RollingUpdate`. **Image tag is CI-managed — keep whatever is current in the repo, don't revert it.** |
| **REPLACE** | `README.md` | Infisical + Postgres |
| **DELETE** | `pvc.yaml` | SQLite hostPath PV/PVC — gone (ArgoCD prunes it; `Retain` keeps the old file on dev01) |
| **DELETE** | `secret.yaml.example` | replaced by Infisical |
| **DELETE** | `sealed-secret.yaml` | if a sealed app secret was ever committed — remove it (the GHCR `sealed-ghcr-secret.yaml` stays) |

## Then (owner)

1. **Infisical `playzy-prd` (env `prd`, path `/`)** — add: `KAGI_SESSION` (the `kagi_session`
   cookie value — no account email/password needed), `PLAYZY_ADMIN_TOKEN`, and
   `PLAYZY_DATABASE_URL = postgres://<user>:<pass>@192.168.219.130:5432/playzy?sslmode=disable&search_path=playzy`
   (user/pass from your `.env`).
2. **Universal-auth bootstrap** — fill + `kubectl apply` the machine-identity clientId/secret
   for `playzy-prd` (see `infisical-credentials.yaml.example`); never commit the filled file.
3. **Commit** the manifest changes → ArgoCD syncs.
4. **Verify** (see `../postgres-k3s-migration.md` §3): the api log shows `quota store: postgres`,
   `/healthz` = ok, `/v1/quota` round-trips, and the tables exist in `playzy.playzy`.

> ⚠️ No SQLite→Postgres data migration. The ledger is small and RevenueCat purchase history is
> authoritative (credits re-grantable idempotently by purchase id). Confirm before cutover.
