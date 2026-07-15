package main

import (
	"path/filepath"
	"testing"
	"time"
)

// authStores returns one of each store implementation so the account/nonce contract
// is verified against both the in-memory and the durable SQLite backend.
func authStores(t *testing.T) map[string]dataStore {
	t.Helper()
	st, err := OpenSQLiteQuotaStore(filepath.Join(t.TempDir(), "auth.db"))
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	t.Cleanup(func() { _ = st.Close() })
	return map[string]dataStore{"memory": NewInMemoryQuotaStore(), "sqlite": st}
}

func TestAccountStore_UpsertIsIdempotentPerIdentity(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	for name, store := range authStores(t) {
		t.Run(name, func(t *testing.T) {
			id1, created1, err := store.UpsertIdentity("https://appleid.apple.com", "sub-A", "a@x.com", now)
			if err != nil || !created1 {
				t.Fatalf("first upsert: id=%q created=%v err=%v", id1, created1, err)
			}
			id2, created2, err := store.UpsertIdentity("https://appleid.apple.com", "sub-A", "a@x.com", now)
			if err != nil || created2 || id2 != id1 {
				t.Fatalf("second upsert should return same account, not create: id=%q created=%v err=%v", id2, created2, err)
			}
			// A different subject (or issuer) is a distinct account.
			id3, created3, _ := store.UpsertIdentity("https://appleid.apple.com", "sub-B", "", now)
			if !created3 || id3 == id1 {
				t.Fatalf("distinct subject must be a new account: id=%q created=%v", id3, created3)
			}
			id4, _, _ := store.UpsertIdentity("https://accounts.google.com", "sub-A", "", now)
			if id4 == id1 {
				t.Fatalf("same subject under a different issuer must be distinct")
			}
		})
	}
}

func TestAccountStore_GetAndDelete(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	for name, store := range authStores(t) {
		t.Run(name, func(t *testing.T) {
			id, _, _ := store.UpsertIdentity("https://appleid.apple.com", "sub-A", "", now)
			acct, err := store.GetAccount(id)
			if err != nil || acct.ID != id || acct.TokenVersion != 0 {
				t.Fatalf("get: %+v err=%v", acct, err)
			}
			if _, err := store.GetAccount("acct_missing"); err != errAccountNotFound {
				t.Fatalf("missing account err = %v, want errAccountNotFound", err)
			}
			if err := store.DeleteAccount(id); err != nil {
				t.Fatalf("delete: %v", err)
			}
			if _, err := store.GetAccount(id); err != errAccountNotFound {
				t.Fatalf("account still present after delete: %v", err)
			}
			// Re-login after delete creates a fresh account (new id).
			id2, created, _ := store.UpsertIdentity("https://appleid.apple.com", "sub-A", "", now)
			if !created || id2 == id {
				t.Fatalf("re-login should create a new account: id=%q created=%v", id2, created)
			}
		})
	}
}

// The SQLite delete cascades to the identity rows (FK ON DELETE CASCADE), so no
// orphan identity can resurrect access.
func TestAccountStore_DeleteCascadesIdentities(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	st, err := OpenSQLiteQuotaStore(filepath.Join(t.TempDir(), "cascade.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })

	id, _, _ := st.UpsertIdentity("https://appleid.apple.com", "sub-A", "", now)
	var before int
	if err := st.db.QueryRow(`SELECT COUNT(*) FROM identity WHERE account_id = ?`, id).Scan(&before); err != nil || before != 1 {
		t.Fatalf("identity count before = %d err=%v", before, err)
	}
	if err := st.DeleteAccount(id); err != nil {
		t.Fatal(err)
	}
	var after int
	if err := st.db.QueryRow(`SELECT COUNT(*) FROM identity WHERE account_id = ?`, id).Scan(&after); err != nil || after != 0 {
		t.Fatalf("identity count after delete = %d err=%v (cascade failed)", after, err)
	}
}

func TestNonceStore_SingleUseAndExpiry(t *testing.T) {
	base := time.Unix(1_700_000_000, 0)
	for name, store := range authStores(t) {
		t.Run(name, func(t *testing.T) {
			nonce, err := store.IssueNonce(base)
			if err != nil || nonce == "" {
				t.Fatalf("issue: %q err=%v", nonce, err)
			}
			// First consume within TTL succeeds.
			ok, err := store.ConsumeNonce(nonce, base.Add(time.Minute))
			if err != nil || !ok {
				t.Fatalf("first consume: ok=%v err=%v", ok, err)
			}
			// Second consume of the same nonce fails (single-use).
			ok, _ = store.ConsumeNonce(nonce, base.Add(2*time.Minute))
			if ok {
				t.Fatal("nonce consumed twice")
			}
			// Consuming an unknown nonce fails.
			if ok, _ := store.ConsumeNonce("never-issued", base); ok {
				t.Fatal("unknown nonce accepted")
			}
			// An expired nonce fails even on first use.
			expired, _ := store.IssueNonce(base)
			if ok, _ := store.ConsumeNonce(expired, base.Add(nonceTTL+time.Second)); ok {
				t.Fatal("expired nonce accepted")
			}
		})
	}
}
