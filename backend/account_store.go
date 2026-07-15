package main

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"time"
)

// Account + auth-nonce persistence (WU3). Both the in-memory (dev) and SQLite
// (durable) quota stores also implement these, so a single store instance backs
// quota, accounts, and nonces.

// account is a Playzy user identity. id is a server-generated opaque token used as
// the durable subject for quota + RevenueCat once auth lands (WU4). tokenVersion
// lets every issued session be invalidated at once (bumped on delete/logout-all).
type account struct {
	ID           string
	CreatedAt    time.Time
	TokenVersion int
}

var errAccountNotFound = errors.New("account not found")

// AccountStore maps external OIDC identities to Playzy accounts.
type AccountStore interface {
	// UpsertIdentity returns the account for (issuer, subject), creating one on first
	// sight. created reports whether a new account was made. email is best-effort.
	UpsertIdentity(issuer, subject, email string, now time.Time) (accountID string, created bool, err error)
	GetAccount(accountID string) (account, error) // errAccountNotFound if absent
	DeleteAccount(accountID string) error          // removes the account + its identities
}

// NonceStore issues single-use, short-lived login nonces so a captured id_token
// can't be replayed against a fresh auth attempt (codex plan C1).
type NonceStore interface {
	IssueNonce(now time.Time) (string, error)
	ConsumeNonce(nonce string, now time.Time) (ok bool, err error)
}

// nonceTTL bounds how long an issued login nonce stays valid.
const nonceTTL = 10 * time.Minute

// newAuthID returns a cryptographically-random id. It FAILS CLOSED on a rand error
// rather than returning a predictable value — a guessable nonce would defeat the
// anti-replay binding and a colliding account id could merge unrelated identities.
func newAuthID(prefix string, n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate id: %w", err)
	}
	return prefix + hex.EncodeToString(b), nil
}

var (
	_ AccountStore = (*InMemoryQuotaStore)(nil)
	_ NonceStore   = (*InMemoryQuotaStore)(nil)
	_ AccountStore = (*SQLiteQuotaStore)(nil)
	_ NonceStore   = (*SQLiteQuotaStore)(nil)
)

// ---- In-memory ----------------------------------------------------------

func identityKey(issuer, subject string) string { return issuer + "\x00" + subject }

func (s *InMemoryQuotaStore) UpsertIdentity(issuer, subject, email string, now time.Time) (string, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := identityKey(issuer, subject)
	if id, ok := s.identities[key]; ok {
		return id, false, nil
	}
	id, err := newAuthID("acct_", 16)
	if err != nil {
		return "", false, err
	}
	s.accounts[id] = &account{ID: id, CreatedAt: now}
	s.identities[key] = id
	return id, true, nil
}

func (s *InMemoryQuotaStore) GetAccount(accountID string) (account, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	a, ok := s.accounts[accountID]
	if !ok {
		return account{}, errAccountNotFound
	}
	return *a, nil
}

func (s *InMemoryQuotaStore) DeleteAccount(accountID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.accounts, accountID)
	for k, id := range s.identities {
		if id == accountID {
			delete(s.identities, k)
		}
	}
	return nil
}

func (s *InMemoryQuotaStore) IssueNonce(now time.Time) (string, error) {
	nonce, err := newAuthID("", 32)
	if err != nil {
		return "", err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sweepNonces(now)
	s.nonces[nonce] = now.Add(nonceTTL)
	return nonce, nil
}

func (s *InMemoryQuotaStore) ConsumeNonce(nonce string, now time.Time) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	exp, ok := s.nonces[nonce]
	if !ok {
		return false, nil
	}
	delete(s.nonces, nonce) // single-use: gone whether or not it was still valid
	return exp.After(now), nil
}

// sweepNonces drops expired nonces. Caller holds the lock.
func (s *InMemoryQuotaStore) sweepNonces(now time.Time) {
	for n, exp := range s.nonces {
		if !exp.After(now) {
			delete(s.nonces, n)
		}
	}
}

// ---- SQLite -------------------------------------------------------------

func (s *SQLiteQuotaStore) UpsertIdentity(issuer, subject, email string, now time.Time) (string, bool, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return "", false, err
	}
	defer func() { _ = tx.Rollback() }()

	var accountID string
	err = tx.QueryRow(`SELECT account_id FROM identity WHERE issuer = ? AND subject = ?`, issuer, subject).
		Scan(&accountID)
	switch {
	case err == nil:
		return accountID, false, nil // existing identity
	case errors.Is(err, sql.ErrNoRows):
		// create below
	default:
		return "", false, err
	}

	accountID, err = newAuthID("acct_", 16)
	if err != nil {
		return "", false, err
	}
	ts := now.Unix()
	if _, err := tx.Exec(`INSERT INTO account(id, created_at, token_version) VALUES(?,?,0)`, accountID, ts); err != nil {
		return "", false, err
	}
	if _, err := tx.Exec(
		`INSERT INTO identity(issuer, subject, email, account_id, created_at) VALUES(?,?,?,?,?)`,
		issuer, subject, email, accountID, ts,
	); err != nil {
		return "", false, err
	}
	if err := tx.Commit(); err != nil {
		return "", false, err
	}
	return accountID, true, nil
}

func (s *SQLiteQuotaStore) GetAccount(accountID string) (account, error) {
	var createdAt int64
	var tokenVersion int
	err := s.db.QueryRow(`SELECT created_at, token_version FROM account WHERE id = ?`, accountID).
		Scan(&createdAt, &tokenVersion)
	if errors.Is(err, sql.ErrNoRows) {
		return account{}, errAccountNotFound
	}
	if err != nil {
		return account{}, err
	}
	return account{ID: accountID, CreatedAt: time.Unix(createdAt, 0), TokenVersion: tokenVersion}, nil
}

func (s *SQLiteQuotaStore) DeleteAccount(accountID string) error {
	// One statement; identity rows cascade (FK ON DELETE CASCADE + foreign_keys=on).
	res, err := s.db.Exec(`DELETE FROM account WHERE id = ?`, accountID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return errAccountNotFound
	}
	return nil
}

func (s *SQLiteQuotaStore) IssueNonce(now time.Time) (string, error) {
	nonce, err := newAuthID("", 32)
	if err != nil {
		return "", err
	}
	if _, err := s.db.Exec(`DELETE FROM auth_nonce WHERE expires_at <= ?`, now.Unix()); err != nil {
		return "", err
	}
	if _, err := s.db.Exec(`INSERT INTO auth_nonce(nonce, expires_at) VALUES(?,?)`, nonce, now.Add(nonceTTL).Unix()); err != nil {
		return "", err
	}
	return nonce, nil
}

func (s *SQLiteQuotaStore) ConsumeNonce(nonce string, now time.Time) (bool, error) {
	// Atomic single-use: delete the row and report whether it existed AND was unexpired.
	var expiresAt int64
	err := s.db.QueryRow(`DELETE FROM auth_nonce WHERE nonce = ? RETURNING expires_at`, nonce).Scan(&expiresAt)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("consume nonce: %w", err)
	}
	return expiresAt > now.Unix(), nil
}
