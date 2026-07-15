package main

import (
	"database/sql"
	"errors"
	"time"
)

// Account-scoped opaque documents (WU6): the app's ChildProfile + character roster,
// synced across a user's devices. The backend stores each as an OPAQUE UTF-8 string
// (it never parses the app schema) keyed by (account, kind). Conflict policy is
// ARRIVAL-ORDER-WINS — an unconditional PUT overwrites; updated_at is informational
// only, not a conflict resolver. (A revision/ETag conditional write is a future add.)

type docKind string

const (
	docProfile docKind = "profile"
	docRoster  docKind = "roster"
)

// maxDocBytes bounds a single document (UTF-8 bytes) so a client can't write
// unbounded rows. The HTTP body cap is larger to allow for JSON string escaping.
const maxDocBytes = 64 * 1024

// DocStore persists per-account opaque documents.
type DocStore interface {
	// GetDoc returns the stored document for (accountID, kind); ok=false when absent.
	GetDoc(accountID string, kind docKind) (doc string, ok bool, err error)
	// PutDoc upserts the document. It must NOT create data for a non-existent account
	// (a delete may race a PUT), so it is bound to account existence.
	PutDoc(accountID string, kind docKind, doc string, now time.Time) error
}

var (
	_ DocStore = (*InMemoryQuotaStore)(nil)
	_ DocStore = (*SQLiteQuotaStore)(nil)
)

func docKey(accountID string, kind docKind) string { return accountID + "\x00" + string(kind) }

// ---- In-memory ----------------------------------------------------------

func (s *InMemoryQuotaStore) GetDoc(accountID string, kind docKind) (string, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	doc, ok := s.docs[docKey(accountID, kind)]
	return doc, ok, nil
}

func (s *InMemoryQuotaStore) PutDoc(accountID string, kind docKind, doc string, _ time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	// Bound to account existence under the same lock a delete takes, so a concurrent
	// delete can't be followed by a resurrecting write (codex plan C1).
	if _, ok := s.accounts[accountID]; !ok {
		return errAccountNotFound
	}
	s.docs[docKey(accountID, kind)] = doc
	return nil
}

// ---- SQLite -------------------------------------------------------------

func (s *SQLiteQuotaStore) GetDoc(accountID string, kind docKind) (string, bool, error) {
	var doc string
	err := s.db.QueryRow(`SELECT doc FROM account_doc WHERE account_id = ? AND kind = ?`, accountID, string(kind)).
		Scan(&doc)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return doc, true, nil
}

func (s *SQLiteQuotaStore) PutDoc(accountID string, kind docKind, doc string, now time.Time) error {
	// The FK (account_doc.account_id → account.id) makes an insert for a deleted
	// account fail rather than resurrect data — account deletion cascades to docs.
	_, err := s.db.Exec(
		`INSERT INTO account_doc(account_id, kind, doc, updated_at) VALUES(?,?,?,?)
		 ON CONFLICT(account_id, kind) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at`,
		accountID, string(kind), doc, now.Unix(),
	)
	return err
}
