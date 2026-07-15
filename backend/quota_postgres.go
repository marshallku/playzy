package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// pgMigrations are the Postgres-dialect equivalents of the sqlite `migrations`
// (same 3 schema versions; see quota_sqlite.go for the design notes). Unix-time
// columns are BIGINT; FKs are enforced natively (no pragma). Applied one
// transaction per step under a cluster-wide advisory lock (pgMigrate), so
// multiple k3s replicas starting at once can't race the DDL (codex review C1).
var pgMigrations = []string{
	// v1 — quota ledger + pending reservations + idempotent credit grants.
	`CREATE TABLE quota(
		device_id TEXT PRIMARY KEY,
		free_used INTEGER NOT NULL DEFAULT 0,
		credits   INTEGER NOT NULL DEFAULT 0
	);
	CREATE TABLE reservation(
		id         TEXT PRIMARY KEY,
		device_id  TEXT NOT NULL,
		source     TEXT NOT NULL CHECK(source IN ('free','credit')),
		created_at BIGINT NOT NULL
	);
	CREATE INDEX reservation_by_device ON reservation(device_id);
	CREATE TABLE credit_grant(
		key        TEXT PRIMARY KEY,
		device_id  TEXT NOT NULL,
		amount     INTEGER NOT NULL CHECK(amount > 0),
		created_at BIGINT NOT NULL
	);`,
	// v2 — user accounts (WU3). See quota_sqlite.go for the model.
	`CREATE TABLE account(
		id            TEXT PRIMARY KEY,
		created_at    BIGINT NOT NULL,
		token_version INTEGER NOT NULL DEFAULT 0
	);
	CREATE TABLE identity(
		issuer     TEXT NOT NULL,
		subject    TEXT NOT NULL,
		email      TEXT NOT NULL DEFAULT '',
		account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
		created_at BIGINT NOT NULL,
		PRIMARY KEY(issuer, subject)
	);
	CREATE INDEX identity_by_account ON identity(account_id);
	CREATE TABLE auth_nonce(
		nonce      TEXT PRIMARY KEY,
		expires_at BIGINT NOT NULL
	);`,
	// v3 — account-scoped opaque documents (WU6): profile + roster JSON.
	`CREATE TABLE account_doc(
		account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
		kind       TEXT NOT NULL CHECK(kind IN ('profile','roster')),
		doc        TEXT NOT NULL,
		updated_at BIGINT NOT NULL,
		PRIMARY KEY(account_id, kind)
	);`,
}

// pgMigrationLockKey is an arbitrary constant advisory-lock id shared by every
// replica so schema migration is serialized cluster-wide.
const pgMigrationLockKey int64 = 0x706c617a79 // "playz"

// Homelab-appropriate pool bounds (codex review I1): a small Postgres shouldn't be
// swamped by an unbounded connection pool under a request spike.
const (
	pgMaxOpenConns    = 10
	pgMaxIdleConns    = 5
	pgConnMaxLifetime = 30 * time.Minute
)

// PostgresQuotaStore is the durable dataStore for horizontal scale (homelab k3s).
// It implements the same QuotaStore+AccountStore+NonceStore+DocStore surface as the
// sqlite store, but — because Postgres runs real concurrency instead of sqlite's
// single-connection serialization — the read-modify-write paths take explicit row
// locks / atomic upserts so concurrent requests can't race (see per-method notes).
type PostgresQuotaStore struct {
	db  *sql.DB
	now clock
}

func OpenPostgresQuotaStore(url string) (*PostgresQuotaStore, error) {
	return openPostgresQuotaStoreClock(url, time.Now)
}

func openPostgresQuotaStoreClock(url string, now clock) (*PostgresQuotaStore, error) {
	db, err := sql.Open("pgx", url)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(pgMaxOpenConns)
	db.SetMaxIdleConns(pgMaxIdleConns)
	db.SetConnMaxLifetime(pgConnMaxLifetime)
	if err := db.PingContext(context.Background()); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("connect postgres: %w", err)
	}
	if err := pgMigrate(db); err != nil {
		_ = db.Close()
		return nil, err
	}
	return &PostgresQuotaStore{db: db, now: now}, nil
}

func (s *PostgresQuotaStore) Close() error { return s.db.Close() }

// pgMigrate advances the schema under a session-level advisory lock held for the
// whole run, so concurrent replicas serialize (only one migrates; the rest observe
// the final version and no-op). One transaction per step; a DB newer than the binary
// is rejected rather than corrupted.
func pgMigrate(db *sql.DB) error {
	ctx := context.Background()
	conn, err := db.Conn(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()

	if _, err := conn.ExecContext(ctx, `SELECT pg_advisory_lock($1)`, pgMigrationLockKey); err != nil {
		return fmt.Errorf("acquire migration lock: %w", err)
	}
	defer func() {
		_, _ = conn.ExecContext(ctx, `SELECT pg_advisory_unlock($1)`, pgMigrationLockKey)
	}()

	if _, err := conn.ExecContext(ctx,
		`CREATE TABLE IF NOT EXISTS schema_version(version INTEGER NOT NULL)`); err != nil {
		return fmt.Errorf("ensure schema_version: %w", err)
	}
	var version int
	err = conn.QueryRowContext(ctx, `SELECT version FROM schema_version LIMIT 1`).Scan(&version)
	if errors.Is(err, sql.ErrNoRows) {
		if _, err := conn.ExecContext(ctx, `INSERT INTO schema_version(version) VALUES(0)`); err != nil {
			return fmt.Errorf("init schema_version: %w", err)
		}
		version = 0
	} else if err != nil {
		return fmt.Errorf("read schema_version: %w", err)
	}
	if version > len(pgMigrations) {
		return fmt.Errorf("database schema version %d is newer than this binary supports (%d)", version, len(pgMigrations))
	}
	for v := version; v < len(pgMigrations); v++ {
		tx, err := conn.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, pgMigrations[v]); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("migration to v%d: %w", v+1, err)
		}
		if _, err := tx.ExecContext(ctx, `UPDATE schema_version SET version = $1`, v+1); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("bump schema_version to %d: %w", v+1, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit migration v%d: %w", v+1, err)
		}
	}
	return nil
}

func (s *PostgresQuotaStore) State(deviceID string) (quotaState, error) {
	var freeUsed, credits int
	err := s.db.QueryRow(`SELECT free_used, credits FROM quota WHERE device_id = $1`, deviceID).
		Scan(&freeUsed, &credits)
	if errors.Is(err, sql.ErrNoRows) {
		return quotaState{FreeLimit: freeStoryLimit, CanGenerate: true}, nil
	}
	if err != nil {
		return quotaState{}, err
	}
	return quotaState{
		FreeUsed:    freeUsed,
		FreeLimit:   freeStoryLimit,
		Credits:     credits,
		CanGenerate: freeUsed < freeStoryLimit || credits > 0,
	}, nil
}

func (s *PostgresQuotaStore) Reserve(deviceID string) (string, error) {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback() }()

	now := s.now().Unix()
	cutoff := s.now().Add(-reservationTTL).Unix()
	if _, err := tx.ExecContext(ctx, `INSERT INTO quota(device_id) VALUES($1) ON CONFLICT DO NOTHING`, deviceID); err != nil {
		return "", err
	}
	// Lock this device's quota row FIRST so concurrent Reserves for the same device
	// serialize (different devices proceed in parallel). Locking quota before any
	// reservation row is the store-wide lock order (Commit and DeleteAccount follow it
	// too), which is what keeps the paths deadlock-free (codex review C1).
	var freeUsed, credits int
	if err := tx.QueryRowContext(ctx, `SELECT free_used, credits FROM quota WHERE device_id = $1 FOR UPDATE`, deviceID).
		Scan(&freeUsed, &credits); err != nil {
		return "", err
	}
	// Housekeeping AFTER the quota lock, scoped to this device (a global cleanup would
	// lock other devices' reservation rows before quota, violating the lock order). The
	// pending-count below already excludes expired holds via `created_at > cutoff`, so
	// this delete only trims storage — it never changes the decision. Other devices'
	// expired rows are trimmed when they next reserve.
	if _, err := tx.ExecContext(ctx, `DELETE FROM reservation WHERE device_id = $1 AND created_at <= $2`, deviceID, cutoff); err != nil {
		return "", err
	}
	var pendingFree, pendingCredit int
	if err := tx.QueryRowContext(ctx, `SELECT
		COALESCE(SUM(CASE WHEN source='free' THEN 1 ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN source='credit' THEN 1 ELSE 0 END), 0)
		FROM reservation WHERE device_id = $1 AND created_at > $2`, deviceID, cutoff).
		Scan(&pendingFree, &pendingCredit); err != nil {
		return "", err
	}
	var source string
	switch {
	case freeStoryLimit-freeUsed-pendingFree > 0:
		source = sourceFree
	case credits-pendingCredit > 0:
		source = sourceCredit
	default:
		return "", errQuotaExceeded
	}
	id := newReservationID()
	if _, err := tx.ExecContext(ctx, `INSERT INTO reservation(id, device_id, source, created_at) VALUES($1,$2,$3,$4)`,
		id, deviceID, source, now); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return id, nil
}

func (s *PostgresQuotaStore) Commit(reservationID string) error {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	// Lock order is quota-row-BEFORE-reservation-row store-wide (codex review C1), so
	// Commit must lock quota first — but it learns the device only from the reservation.
	// Read the reservation without a lock (its device_id/source are immutable once
	// created), then lock the quota row, then claim the reservation.
	var deviceID, source string
	err = tx.QueryRowContext(ctx, `SELECT device_id, source FROM reservation WHERE id = $1`, reservationID).
		Scan(&deviceID, &source)
	if errors.Is(err, sql.ErrNoRows) {
		return nil // already committed/released — idempotent no-op
	}
	if err != nil {
		return err
	}
	// Lock the quota row (consistent order). If it's gone, DeleteAccount has purged the
	// subject — the reservation is being removed with it; treat as a no-op.
	var locked string
	err = tx.QueryRowContext(ctx, `SELECT device_id FROM quota WHERE device_id = $1 FOR UPDATE`, deviceID).Scan(&locked)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	// Claim the reservation now that quota is locked. If a concurrent Release deleted it
	// first, RowsAffected is 0 — nothing was charged, which is the correct outcome for a
	// released hold (removes the read-then-charge window; codex review C3).
	claim, err := tx.ExecContext(ctx, `DELETE FROM reservation WHERE id = $1`, reservationID)
	if err != nil {
		return err
	}
	if n, _ := claim.RowsAffected(); n == 0 {
		return nil
	}
	switch source {
	case sourceFree:
		if _, err := tx.ExecContext(ctx, `UPDATE quota SET free_used = free_used + 1 WHERE device_id = $1`, deviceID); err != nil {
			return err
		}
	case sourceCredit:
		res, err := tx.ExecContext(ctx, `UPDATE quota SET credits = credits - 1 WHERE device_id = $1 AND credits > 0`, deviceID)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			// The hold outlived its allowance (pathological clock jump). The
			// reservation is already claimed (deleted above); commit and report
			// "not charged" rather than driving credits negative.
			if err := tx.Commit(); err != nil {
				return err
			}
			return errCreditUnderflow
		}
	}
	return tx.Commit()
}

func (s *PostgresQuotaStore) Release(reservationID string) {
	if _, err := s.db.Exec(`DELETE FROM reservation WHERE id = $1`, reservationID); err != nil {
		log.Printf("quota release %s: %v", reservationID, err)
	}
}

func (s *PostgresQuotaStore) AddCredits(deviceID string, n int, key string) error {
	if n <= 0 || n > maxGrant {
		return fmt.Errorf("invalid grant amount %d", n)
	}
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := tx.ExecContext(ctx, `INSERT INTO quota(device_id) VALUES($1) ON CONFLICT DO NOTHING`, deviceID); err != nil {
		return err
	}
	// Serialize credit application for this device (vs Reserve / DeleteAccount).
	var freeUsed, credits int
	if err := tx.QueryRowContext(ctx, `SELECT free_used, credits FROM quota WHERE device_id = $1 FOR UPDATE`, deviceID).
		Scan(&freeUsed, &credits); err != nil {
		return err
	}
	// Atomically claim the idempotency key. ON CONFLICT DO NOTHING RETURNING means a
	// concurrent same-key grant can't both insert-then-error: the loser gets
	// ErrNoRows and falls through to the idempotent/conflict check (codex review C6).
	var claimed string
	err = tx.QueryRowContext(ctx,
		`INSERT INTO credit_grant(key, device_id, amount, created_at) VALUES($1,$2,$3,$4)
		 ON CONFLICT(key) DO NOTHING RETURNING key`,
		key, deviceID, n, s.now().Unix()).Scan(&claimed)
	if errors.Is(err, sql.ErrNoRows) {
		var exDevice string
		var exAmount int
		if err := tx.QueryRowContext(ctx, `SELECT device_id, amount FROM credit_grant WHERE key = $1`, key).
			Scan(&exDevice, &exAmount); err != nil {
			return err
		}
		if exDevice == deviceID && exAmount == n {
			return tx.Commit() // idempotent replay — no double credit
		}
		return errGrantConflict
	}
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE quota SET credits = credits + $1 WHERE device_id = $2`, n, deviceID); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *PostgresQuotaStore) UpsertIdentity(issuer, subject, email string, now time.Time) (string, bool, error) {
	ctx := context.Background()
	// Fast path: identity already exists.
	var accountID string
	err := s.db.QueryRowContext(ctx, `SELECT account_id FROM identity WHERE issuer = $1 AND subject = $2`, issuer, subject).
		Scan(&accountID)
	if err == nil {
		return accountID, false, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", false, err
	}

	newID, err := newAuthID(accountIDPrefix, 16)
	if err != nil {
		return "", false, err
	}
	ts := now.Unix()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return "", false, err
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := tx.ExecContext(ctx, `INSERT INTO account(id, created_at, token_version) VALUES($1,$2,0)`, newID, ts); err != nil {
		return "", false, err
	}
	// Atomic create: if a concurrent first sign-in for the same (issuer, subject) won,
	// the conflicting insert does nothing and returns no row — we roll back our orphan
	// account and read the winning account instead (codex review C2).
	var got string
	err = tx.QueryRowContext(ctx,
		`INSERT INTO identity(issuer, subject, email, account_id, created_at) VALUES($1,$2,$3,$4,$5)
		 ON CONFLICT(issuer, subject) DO NOTHING RETURNING account_id`,
		issuer, subject, email, newID, ts).Scan(&got)
	if err == nil {
		if err := tx.Commit(); err != nil {
			return "", false, err
		}
		return newID, true, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", false, err
	}
	// Lost the race: discard the orphan account and return the winner.
	_ = tx.Rollback()
	if err := s.db.QueryRowContext(ctx, `SELECT account_id FROM identity WHERE issuer = $1 AND subject = $2`, issuer, subject).
		Scan(&accountID); err != nil {
		return "", false, err
	}
	return accountID, false, nil
}

func (s *PostgresQuotaStore) GetAccount(accountID string) (account, error) {
	var createdAt int64
	var tokenVersion int
	err := s.db.QueryRow(`SELECT created_at, token_version FROM account WHERE id = $1`, accountID).
		Scan(&createdAt, &tokenVersion)
	if errors.Is(err, sql.ErrNoRows) {
		return account{}, errAccountNotFound
	}
	if err != nil {
		return account{}, err
	}
	return account{ID: accountID, CreatedAt: time.Unix(createdAt, 0), TokenVersion: tokenVersion}, nil
}

func (s *PostgresQuotaStore) DeleteAccount(accountID string) error {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	res, err := tx.ExecContext(ctx, `DELETE FROM account WHERE id = $1`, accountID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return errAccountNotFound
	}
	// Lock the account's quota row first (if any) so a concurrent Reserve/AddCredits
	// for the same subject can't interleave mid-purge and leave a torn state — matches
	// the sqlite store's effective single-writer guarantee (codex review C4).
	//
	// SCOPE (system-wide, NOT specific to this store): a Reserve/AddCredits that starts
	// entirely AFTER this delete commits can recreate a quota row — quota is keyed by an
	// opaque subject with no FK to account (anonymous device subjects have no account),
	// so the store can't refuse the recreation. sqlite and memory have the identical
	// property. The authed Reserve path is narrowed by requireAccount revalidating the
	// account every request (a deleted account's token 401s), but the admin/webhook
	// AddCredits path does not check account existence. Fully closing that (a tombstone,
	// or an account-existence check in the credit-grant handler) is a cross-cutting
	// deletion-integrity follow-up, tracked in docs/planning/71 — deliberately out of
	// this store-port unit so the check lives in one place across all stores.
	if _, err := tx.ExecContext(ctx, `SELECT device_id FROM quota WHERE device_id = $1 FOR UPDATE`, accountID); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	// identity rows cascade (FK). Purge every other subject-keyed table.
	for _, q := range []string{
		`DELETE FROM quota WHERE device_id = $1`,
		`DELETE FROM credit_grant WHERE device_id = $1`,
		`DELETE FROM reservation WHERE device_id = $1`,
	} {
		if _, err := tx.ExecContext(ctx, q, accountID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *PostgresQuotaStore) IssueNonce(now time.Time) (string, error) {
	nonce, err := newAuthID("", 32)
	if err != nil {
		return "", err
	}
	if _, err := s.db.Exec(`DELETE FROM auth_nonce WHERE expires_at <= $1`, now.Unix()); err != nil {
		return "", err
	}
	if _, err := s.db.Exec(`INSERT INTO auth_nonce(nonce, expires_at) VALUES($1,$2)`, nonce, now.Add(nonceTTL).Unix()); err != nil {
		return "", err
	}
	return nonce, nil
}

func (s *PostgresQuotaStore) ConsumeNonce(nonce string, now time.Time) (bool, error) {
	// Atomic single-use: delete the row and report whether it existed AND was unexpired.
	var expiresAt int64
	err := s.db.QueryRow(`DELETE FROM auth_nonce WHERE nonce = $1 RETURNING expires_at`, nonce).Scan(&expiresAt)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("consume nonce: %w", err)
	}
	return expiresAt > now.Unix(), nil
}

func (s *PostgresQuotaStore) GetDoc(accountID string, kind docKind) (string, bool, error) {
	var doc string
	err := s.db.QueryRow(`SELECT doc FROM account_doc WHERE account_id = $1 AND kind = $2`, accountID, string(kind)).
		Scan(&doc)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return doc, true, nil
}

func (s *PostgresQuotaStore) PutDoc(accountID string, kind docKind, doc string, now time.Time) error {
	// The FK (account_doc.account_id → account.id) makes an insert for a deleted
	// account fail rather than resurrect data — account deletion cascades to docs.
	_, err := s.db.Exec(
		`INSERT INTO account_doc(account_id, kind, doc, updated_at) VALUES($1,$2,$3,$4)
		 ON CONFLICT(account_id, kind) DO UPDATE SET doc = EXCLUDED.doc, updated_at = EXCLUDED.updated_at`,
		accountID, string(kind), doc, now.Unix(),
	)
	return err
}
