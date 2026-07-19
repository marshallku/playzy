# playzy (prd)

Production deployment for **playzy** — the toddler bedtime-story app
([`playzy`](https://github.com/marshallku/playzy) repo). One surface:

- **playzy-api** — Go single binary (`backend/`), the AI gateway between the
  Flutter app and the AI provider (ADR 0001). Exposes the stable Playzy story
  contract (`POST /v1/stories`, `GET /v1/quota`, `POST /v1/credits`,
  `GET /v1/catalog/situations`, `GET /healthz`) and enforces the authoritative
  free-tier + credit quota (ADR 0002), plus accounts/profiles, in db01 Postgres
  (the `playzy` database, `playzy` schema).

The mobile app is the only client; there is no web frontend deployed here. Point
a build at the API with
`flutter build --dart-define=PLAYZY_API_BASE_URL=https://api-playzy.marshallku.dev`.

## AI backend (kagi-serve sidecar)

kagi is a **reverse-engineered, unofficial, dev/personal** Kagi Assistant client
(ADR 0001) — not shippable inside the app and single-user. It runs as a **native
sidecar** (initContainer with `restartPolicy: Always`, image
`ghcr.io/marshallku/kagi`) in the same pod as the api, hosting `/chat` on
`localhost:8921`. The api reaches it via `KAGI_SERVE_URL=http://127.0.0.1:8921`.
This mirrors the irang wiring. Swapping to a real provider (OpenAI/Anthropic) is
a server-side change confined to `callAI` in `backend/main.go` — the app never
changes.

## Differences from `maji/` and `irang/`

| Concern | maji/irang prd | playzy prd |
| --- | --- | --- |
| Namespace | `maji` / `irang` | `playzy` |
| Secret backend | SealedSecret / Infisical | **Infisical** (`playzy-prd` project) — GHCR pull secret stays SealedSecret |
| Cloudflare account | sssup (`maji.you`, `irang.me`) | **marshallku.dev** — served by the `cloudflared/` deployment, not `cloudflared-sssup/` |
| API domain | `api.maji.you` / `api.irang.me` | `api-playzy.marshallku.dev` |
| Web domain | root zone | `playzy.marshallku.dev` (wired separately by the owner; not served here) |
| Datastore | Postgres on db01 | **Postgres on db01** — own `playzy` database + `playzy` schema |
| AI backend | kagi-serve sidecar | **same** kagi-serve sidecar |
| NodePort | 30500/30501/30504/… | **30511** (api) |

## Layout

```
playzy/
├── namespace.yaml
├── api/{deployment,service}.yaml     # api container + kagi-serve sidecar, NodePort 30511
├── infisical-secret.yaml             # InfisicalSecret CR → syncs the `playzy-secret` (commit)
├── infisical-credentials.yaml.example# template for the universal-auth bootstrap (apply once)
├── sealed-ghcr-secret.yaml.example   # template → seal to sealed-ghcr-secret.yaml
└── argocd-application.yaml.example   # register with ArgoCD (apply once, by hand)
```

Secrets: the app secret (`playzy-secret`) is synced from the **Infisical** `playzy-prd`
project by the operator — nothing plaintext is committed. The GHCR pull secret stays a
SealedSecret. Files committed to git: everything except `infisical-credentials.yaml`
(plaintext universal-auth, applied manually once) and any unsealed `*.yaml` from the
`.example` templates.

## Bootstrap

1. **Database (db01 Postgres).** Already provisioned: the `playzy` database + `playzy`
   schema exist and the backend's tables are migrated (`schema_version = 3`). See the
   playzy repo's `docs/deploy/postgres-k3s-migration.md`. Nothing to do here unless
   re-provisioning a fresh instance (the backend re-runs its migrations at startup).

2. **App secret (Infisical).** In the Infisical `playzy-prd` project (env `prd`,
   path `/`), add these secrets:

   | Key | Value |
   | --- | --- |
   | `KAGI_SESSION` | the `kagi_session` cookie value (no account email/password needed) |
   | `PLAYZY_ADMIN_TOKEN` | guards `POST /v1/credits` (leave empty to disable) |
   | `PLAYZY_DATABASE_URL` | `postgres://<user>:<pass>@192.168.219.130:5432/playzy?sslmode=disable&search_path=playzy` |

   Then bootstrap the operator's read credentials once (machine identity for
   `playzy-prd`):

   ```sh
   cp infisical-credentials.yaml.example /tmp/playzy-infisical-credentials.yaml
   # fill clientId / clientSecret
   kubectl apply -f /tmp/playzy-infisical-credentials.yaml
   rm /tmp/playzy-infisical-credentials.yaml
   ```

   `infisical-secret.yaml` (committed) then makes the operator sync `playzy-secret`.

3. **GHCR pull secret.** Follow `sealed-ghcr-secret.yaml.example` to generate
   `sealed-ghcr-secret.yaml` (namespace `playzy`).

4. **Register with ArgoCD** (once):

   ```sh
   kubectl apply -f kubernetes/service/playzy/argocd-application.yaml.example
   ```

5. **Public hostname.** In the Cloudflare Zero Trust dashboard (the
   **marshallku.dev** account, served by the existing `cloudflared/` tunnel), add
   a public hostname `api-playzy.marshallku.dev` → `http://<node-ip>:30511`.
   Ingress rules are managed in the dashboard (remotely-managed tunnel), not in
   this repo.

## CI/CD

The [`playzy`](https://github.com/marshallku/playzy) repo's
`deploy-backend.yml` builds `ghcr.io/marshallku/playzy-backend`, pushes `:prd`
and `:<sha>`, then bumps the image tag in `api/deployment.yaml` here and pushes —
ArgoCD syncs the new SHA. It needs a `MANIFEST_REPO_TOKEN` secret (write access
to this repo), the same pattern maji/irang use.
