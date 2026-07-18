# Prod migration: SQLite-on-PVC → Postgres on db01 (k3s / ArgoCD)

**Status:** prepared for review — NOT applied. The k8s manifests live in the private
GitOps repo `marshallku/manifest` under `kubernetes/service/playzy/`; ArgoCD auto-syncs it,
so **pushing there deploys to prod**. This doc has the exact changes to make there, plus the
db01 provisioning + seal/apply/verify steps. The app side is already shipped:
`PLAYZY_QUOTA_STORE=postgres` + `PLAYZY_DATABASE_URL` (backend commit `a919451`).

Topology chosen: **db01 shared Postgres** (the maji/irang pattern), prepare-for-review.

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

## 2. `kubernetes/service/playzy/secret.yaml.example` — add the DB URL key

Add `PLAYZY_DATABASE_URL` to the `stringData` block and document it:

```yaml
stringData:
  KAGI_EMAIL: ""
  KAGI_PASSWORD: ""
  PLAYZY_ADMIN_TOKEN: ""
  # Postgres connection URL for the durable quota/account store (db01, playzy schema).
  #   postgres://<user>:<password>@192.168.219.130:5432/playzy?sslmode=disable&search_path=playzy
  PLAYZY_DATABASE_URL: ""
```

Then re-seal (the plaintext is gitignored):

```sh
cp secret.yaml.example /tmp/playzy-secret.yaml
# edit /tmp/playzy-secret.yaml — fill KAGI_*, PLAYZY_ADMIN_TOKEN, and PLAYZY_DATABASE_URL
kubeseal --controller-namespace kube-system --controller-name sealed-secrets \
  --format yaml < /tmp/playzy-secret.yaml > sealed-secret.yaml
rm /tmp/playzy-secret.yaml
```

---

## 3. `kubernetes/service/playzy/api/deployment.yaml` — swap the store

Full revised Deployment (kagi sidecar unchanged; SQLite volume/PVC + dev01 pin removed;
store env swapped; `Recreate` → `RollingUpdate` since Postgres has no single-writer file):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: playzy-api
  namespace: playzy
  labels:
    app: playzy-api
spec:
  replicas: 1 # safe to scale >1 now — the Postgres store is multi-replica-safe
  # Postgres is a remote shared DB (no single-writer file), so a rolling update is fine.
  strategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app: playzy-api
  template:
    metadata:
      labels:
        app: playzy-api
    spec:
      imagePullSecrets:
        - name: ghcr-secret
      # nodeSelector removed: the pod no longer needs the dev01 hostPath volume.
      initContainers:
        - name: kagi-serve
          image: ghcr.io/marshallku/kagi:0ca3adfdf4dd4c6116d386f82b0ebff5f3f781c8
          restartPolicy: Always
          args: ["serve", "-addr", "0.0.0.0:8921"]
          ports:
            - containerPort: 8921
          env:
            - name: KAGI_EMAIL
              valueFrom:
                secretKeyRef: { name: playzy-secret, key: KAGI_EMAIL }
            - name: KAGI_PASSWORD
              valueFrom:
                secretKeyRef: { name: playzy-secret, key: KAGI_PASSWORD }
          resources:
            requests: { cpu: 20m, memory: 32Mi }
            limits: { memory: 128Mi }
          readinessProbe:
            httpGet: { path: /healthz, port: 8921 }
            initialDelaySeconds: 2
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: /healthz, port: 8921 }
            initialDelaySeconds: 15
            periodSeconds: 30
      containers:
        - name: api
          image: ghcr.io/marshallku/playzy-backend:196669168c8a80303018fa06f6cab6ffb81a5d75 # bumped by CI
          ports:
            - containerPort: 8080
          env:
            - name: PLAYZY_ADDR
              value: ":8080"
            - name: KAGI_SERVE_URL
              value: http://127.0.0.1:8921
            - name: KAGI_MODEL
              value: claude-5-sonnet
            # Durable authoritative quota/account store on db01 Postgres (ADR 0002).
            # Fail-closed: a missing URL aborts boot rather than using a volatile store.
            - name: PLAYZY_QUOTA_STORE
              value: postgres
            - name: PLAYZY_DATABASE_URL
              valueFrom:
                secretKeyRef: { name: playzy-secret, key: PLAYZY_DATABASE_URL }
            - name: PLAYZY_ADMIN_TOKEN
              valueFrom:
                secretKeyRef: { name: playzy-secret, key: PLAYZY_ADMIN_TOKEN }
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { memory: 256Mi }
          readinessProbe:
            httpGet: { path: /healthz, port: 8080 }
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet: { path: /healthz, port: 8080 }
            initialDelaySeconds: 10
            periodSeconds: 15
      # volumes removed (no SQLite PVC)
```

> Keep `api/service.yaml` (NodePort 30511) exactly as-is — the Cloudflare tunnel targets it.

---

## 4. Delete `kubernetes/service/playzy/pvc.yaml`

The SQLite hostPath PV/PVC is no longer used. Remove the file. Because ArgoCD prunes, the
`playzy-data` PVC and `playzy-data-pv` are deleted on sync — the `Retain` reclaim policy
keeps the old SQLite file on dev01 (`/mnt/hdd/data/dev01/playzy`) if you want to archive the
pre-migration ledger; delete it manually afterward.

> ⚠️ There is **no automatic data migration** from the SQLite ledger to Postgres. At current
> scale the quota/credit ledger is small; the authoritative source is the RevenueCat purchase
> history (credits can be re-granted idempotently by purchase id). If any live credits exist,
> reconcile them before cutover, or grant a one-time bridge via `POST /v1/credits`. Confirm
> this is acceptable before applying.

---

## 5. README.md updates (`kubernetes/service/playzy/README.md`)

- Datastore row: ~~local SQLite on a dev01 hostPath PVC~~ → **Postgres on db01** (now matches
  maji/irang).
- Layout: drop `pvc.yaml`.
- Bootstrap: remove the "Sidecar node storage / hostPath" step; add "create the `playzy` DB +
  role on db01" (§1 above) and the `PLAYZY_DATABASE_URL` secret key (§2).

---

## 6. Apply (owner)

1. Commit the changed `sealed-secret.yaml`, `api/deployment.yaml`, README, and the `pvc.yaml`
   deletion to `marshallku/manifest`.
2. ArgoCD syncs. Watch the rollout: `kubectl -n playzy rollout status deploy/playzy-api`.
3. **Verify:**
   - `kubectl -n playzy logs deploy/playzy-api -c api` → shows `quota store: postgres`, no
     migration errors.
   - `curl https://api-playzy.marshallku.dev/healthz` → `ok`.
   - `curl https://api-playzy.marshallku.dev/v1/quota -H 'X-Device-Id: smoke-test'` → a fresh
     free-tier allowance (proves the store round-trips).
   - On db01: `\dt` in the `playzy` DB shows `quota`, `reservation`, `credit_grant`, `account`,
     `identity`, `auth_nonce`, `account_doc`, `schema_version`.

---

## Rollback

Revert the manifest commit (ArgoCD re-syncs to SQLite-on-PVC). The `Retain` PV keeps the old
SQLite file, so the previous ledger is intact if you didn't delete it.
