package main

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"time"

	_ "modernc.org/sqlite"
)

// migrations are ordered, forward-only schema steps. Index i builds schema
// version i+1. migrate() applies each in its own transaction together with the
// user_version bump, so an interrupted migration never leaves a half-applied
// schema marked as done.
var migrations = []string{
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
		created_at INTEGER NOT NULL
	);
	CREATE INDEX reservation_by_device ON reservation(device_id);
	CREATE TABLE credit_grant(
		key        TEXT PRIMARY KEY,
		device_id  TEXT NOT NULL,
		amount     INTEGER NOT NULL CHECK(amount > 0),
		created_at INTEGER NOT NULL
	);`,
	// v2 — user accounts (WU3). An account is a server-generated id; an identity
	// is a (provider issuer, subject) pair pointing at it (a person can sign in
	// with multiple providers, each a distinct identity until linking lands).
	// token_version invalidates all of an account's sessions when bumped. Deleting
	// an account cascades to its identities (FKs are enabled via the DSN pragma).
	// auth_nonce holds server-issued single-use login nonces (OIDC anti-replay).
	`CREATE TABLE account(
		id            TEXT PRIMARY KEY,
		created_at    INTEGER NOT NULL,
		token_version INTEGER NOT NULL DEFAULT 0
	);
	CREATE TABLE identity(
		issuer     TEXT NOT NULL,
		subject    TEXT NOT NULL,
		email      TEXT NOT NULL DEFAULT '',
		account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
		created_at INTEGER NOT NULL,
		PRIMARY KEY(issuer, subject)
	);
	CREATE INDEX identity_by_account ON identity(account_id);
	CREATE TABLE auth_nonce(
		nonce      TEXT PRIMARY KEY,
		expires_at INTEGER NOT NULL
	);`,
	// v3 — account-scoped opaque documents (WU6): the app's profile + roster JSON,
	// keyed by (account, kind). FK cascade so deleting an account removes its docs
	// (and an insert for a deleted account fails rather than resurrecting data).
	`CREATE TABLE account_doc(
		account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
		kind       TEXT NOT NULL CHECK(kind IN ('profile','roster')),
		doc        TEXT NOT NULL,
		updated_at INTEGER NOT NULL,
		PRIMARY KEY(account_id, kind)
	);`,
}

// SQLiteQuotaStore is the durable QuotaStore (pure-Go modernc.org/sqlite, no cgo
// — ADR 0005). Launch scale is a single instance; horizontal scale swaps this
// for Postgres behind the same interface. One connection serializes access,
// which keeps the reserve/commit transactions correct without SQLITE_BUSY
// handling; State uses a plain read so it never holds a write lock.
type SQLiteQuotaStore struct {
	db  *sql.DB
	now clock
}

func OpenSQLiteQuotaStore(path string) (*SQLiteQuotaStore, error) {
	return openSQLiteQuotaStoreClock(path, time.Now)
}

func openSQLiteQuotaStoreClock(path string, now clock) (*SQLiteQuotaStore, error) {
	dsn := fmt.Sprintf(
		"file:%s?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(on)",
		path,
	)
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1) // serialize; correctness-first at launch scale
	if err := migrate(db); err != nil {
		_ = db.Close()
		return nil, err
	}
	return &SQLiteQuotaStore{db: db, now: now}, nil
}

func (s *SQLiteQuotaStore) Close() error { return s.db.Close() }

// migrate advances the schema to the version this binary knows, one transaction
// per step. A database newer than the binary is rejected rather than corrupted.
func migrate(db *sql.DB) error {
	var version int
	if err := db.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		return fmt.Errorf("read user_version: %w", err)
	}
	if version > len(migrations) {
		return fmt.Errorf("database schema version %d is newer than this binary supports (%d)", version, len(migrations))
	}
	for v := version; v < len(migrations); v++ {
		tx, err := db.Begin()
		if err != nil {
			return err
		}
		if _, err := tx.Exec(migrations[v]); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("migration to v%d: %w", v+1, err)
		}
		// user_version can't be parameterized; the value is our own slice index.
		if _, err := tx.Exec(fmt.Sprintf("PRAGMA user_version = %d", v+1)); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("bump user_version to %d: %w", v+1, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit migration v%d: %w", v+1, err)
		}
	}
	return nil
}

func (s *SQLiteQuotaStore) State(deviceID string) (quotaState, error) {
	var freeUsed, credits int
	err := s.db.QueryRow(`SELECT free_used, credits FROM quota WHERE device_id = ?`, deviceID).
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

func (s *SQLiteQuotaStore) Reserve(deviceID string) (string, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback() }()

	now := s.now().Unix()
	cutoff := s.now().Add(-reservationTTL).Unix()
	// Opportunistically drop expired holds so they stop counting against anyone.
	if _, err := tx.Exec(`DELETE FROM reservation WHERE created_at <= ?`, cutoff); err != nil {
		return "", err
	}
	if _, err := tx.Exec(`INSERT OR IGNORE INTO quota(device_id) VALUES(?)`, deviceID); err != nil {
		return "", err
	}
	var freeUsed, credits int
	if err := tx.QueryRow(`SELECT free_used, credits FROM quota WHERE device_id = ?`, deviceID).
		Scan(&freeUsed, &credits); err != nil {
		return "", err
	}
	var pendingFree, pendingCredit int
	if err := tx.QueryRow(`SELECT
		COALESCE(SUM(CASE WHEN source='free' THEN 1 ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN source='credit' THEN 1 ELSE 0 END), 0)
		FROM reservation WHERE device_id = ? AND created_at > ?`, deviceID, cutoff).
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
	if _, err := tx.Exec(`INSERT INTO reservation(id, device_id, source, created_at) VALUES(?,?,?,?)`,
		id, deviceID, source, now); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return id, nil
}

func (s *SQLiteQuotaStore) Commit(reservationID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var deviceID, source string
	err = tx.QueryRow(`SELECT device_id, source FROM reservation WHERE id = ?`, reservationID).
		Scan(&deviceID, &source)
	if errors.Is(err, sql.ErrNoRows) {
		return nil // already committed/released — idempotent
	}
	if err != nil {
		return err
	}
	// Commit is authoritative regardless of TTL: a hold that still exists is
	// committable. TTL only governs availability for NEW reserves, so a real
	// in-flight generation (<< TTL) always commits cleanly.
	switch source {
	case sourceFree:
		if _, err := tx.Exec(`UPDATE quota SET free_used = free_used + 1 WHERE device_id = ?`, deviceID); err != nil {
			return err
		}
	case sourceCredit:
		res, err := tx.Exec(`UPDATE quota SET credits = credits - 1 WHERE device_id = ? AND credits > 0`, deviceID)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			// The hold outlived its allowance (pathological clock jump). Drop it
			// rather than driving credits negative; report "not charged".
			if _, err := tx.Exec(`DELETE FROM reservation WHERE id = ?`, reservationID); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			return errCreditUnderflow
		}
	}
	if _, err := tx.Exec(`DELETE FROM reservation WHERE id = ?`, reservationID); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *SQLiteQuotaStore) Release(reservationID string) {
	if _, err := s.db.Exec(`DELETE FROM reservation WHERE id = ?`, reservationID); err != nil {
		log.Printf("quota release %s: %v", reservationID, err)
	}
}

func (s *SQLiteQuotaStore) AddCredits(deviceID string, n int, key string) error {
	if n <= 0 || n > maxGrant {
		return fmt.Errorf("invalid grant amount %d", n)
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var exDevice string
	var exAmount int
	err = tx.QueryRow(`SELECT device_id, amount FROM credit_grant WHERE key = ?`, key).
		Scan(&exDevice, &exAmount)
	switch {
	case err == nil:
		if exDevice == deviceID && exAmount == n {
			return nil // idempotent replay
		}
		return errGrantConflict
	case errors.Is(err, sql.ErrNoRows):
		// new grant — apply below
	default:
		return err
	}
	if _, err := tx.Exec(`INSERT INTO credit_grant(key, device_id, amount, created_at) VALUES(?,?,?,?)`,
		key, deviceID, n, s.now().Unix()); err != nil {
		return err
	}
	if _, err := tx.Exec(`INSERT OR IGNORE INTO quota(device_id) VALUES(?)`, deviceID); err != nil {
		return err
	}
	if _, err := tx.Exec(`UPDATE quota SET credits = credits + ? WHERE device_id = ?`, n, deviceID); err != nil {
		return err
	}
	return tx.Commit()
}
