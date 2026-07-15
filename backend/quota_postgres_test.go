package main

import (
	"database/sql"
	"fmt"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// pgTestSchemaSeq gives each opened test store a unique schema so runs are isolated
// on a shared Postgres (search_path is encoded in the DSN, so it applies to every
// pooled connection — codex review C5).
var pgTestSchemaSeq atomic.Int64

// openPostgresTestStore opens a Postgres store in a fresh, isolated schema, or skips
// the test when PLAYZY_TEST_DATABASE_URL is unset. Spin up a throwaway PG with:
//
//	docker run -d -e POSTGRES_PASSWORD=test -e POSTGRES_DB=playzy -p 55432:5432 postgres:16
//	PLAYZY_TEST_DATABASE_URL='postgres://postgres:test@localhost:55432/playzy?sslmode=disable' go test ./...
func openPostgresTestStore(t *testing.T, now clock) *PostgresQuotaStore {
	t.Helper()
	base := os.Getenv("PLAYZY_TEST_DATABASE_URL")
	if base == "" {
		t.Skip("PLAYZY_TEST_DATABASE_URL not set — skipping Postgres store tests")
	}
	schema := fmt.Sprintf("t_%d_%d", os.Getpid(), pgTestSchemaSeq.Add(1))

	// Create the schema on a plain connection first (the store's migrations then build
	// their tables inside it via the search_path in the DSN).
	admin, err := sql.Open("pgx", base)
	if err != nil {
		t.Fatalf("open admin conn: %v", err)
	}
	if _, err := admin.Exec(fmt.Sprintf(`CREATE SCHEMA %q`, schema)); err != nil {
		_ = admin.Close()
		t.Fatalf("create schema: %v", err)
	}
	_ = admin.Close()

	sep := "?"
	if strings.Contains(base, "?") {
		sep = "&"
	}
	url := base + sep + "search_path=" + schema

	s, err := openPostgresQuotaStoreClock(url, now)
	if err != nil {
		t.Fatalf("open postgres store: %v", err)
	}
	t.Cleanup(func() {
		_ = s.Close()
		if admin, err := sql.Open("pgx", base); err == nil {
			_, _ = admin.Exec(fmt.Sprintf(`DROP SCHEMA %q CASCADE`, schema))
			_ = admin.Close()
		}
	})
	return s
}

// TestPostgresStore_MigrateIsIdempotent re-running migration on an up-to-date schema
// is a no-op (the advisory-locked version check short-circuits).
func TestPostgresStore_MigrateIsIdempotent(t *testing.T) {
	s := openPostgresTestStore(t, time.Now)
	if err := pgMigrate(s.db); err != nil {
		t.Fatalf("second migrate: %v", err)
	}
}

// TestPostgresStore_ConcurrentUpsertIdentitySameSubject — concurrent first sign-ins
// for the same (issuer, subject) must yield exactly one account, all callers agreeing
// (codex review C2). Requires the real concurrency of Postgres, so it's PG-only.
func TestPostgresStore_ConcurrentUpsertIdentitySameSubject(t *testing.T) {
	s := openPostgresTestStore(t, time.Now)
	const n = 12
	var wg sync.WaitGroup
	ids := make([]string, n)
	created := make([]bool, n)
	errs := make([]error, n)
	start := make(chan struct{})
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			ids[i], created[i], errs[i] = s.UpsertIdentity("iss", "sub-1", "e@x.com", time.Now())
		}(i)
	}
	close(start)
	wg.Wait()

	createdCount := 0
	for i := 0; i < n; i++ {
		if errs[i] != nil {
			t.Fatalf("goroutine %d: %v", i, errs[i])
		}
		if created[i] {
			createdCount++
		}
		if ids[i] != ids[0] {
			t.Fatalf("account id mismatch: %q vs %q", ids[i], ids[0])
		}
	}
	if createdCount != 1 {
		t.Fatalf("expected exactly one account created, got %d", createdCount)
	}
}

// TestPostgresStore_ConcurrentAddCreditsSameKey — concurrent grants with the same
// idempotency key must apply exactly once, none erroring (codex review C6).
func TestPostgresStore_ConcurrentAddCreditsSameKey(t *testing.T) {
	s := openPostgresTestStore(t, time.Now)
	const n = 12
	var wg sync.WaitGroup
	errs := make([]error, n)
	start := make(chan struct{})
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			errs[i] = s.AddCredits("dev-x", 10, "purchase-key-1")
		}(i)
	}
	close(start)
	wg.Wait()

	for i := 0; i < n; i++ {
		if errs[i] != nil {
			t.Fatalf("goroutine %d: %v", i, errs[i])
		}
	}
	st, err := s.State("dev-x")
	if err != nil {
		t.Fatalf("state: %v", err)
	}
	if st.Credits != 10 {
		t.Fatalf("credits = %d, want 10 (applied exactly once)", st.Credits)
	}
}

// TestPostgresStore_AddCreditsConflictingKey — reusing a key with a different
// (device, amount) is a conflict, not a silent regrant.
func TestPostgresStore_AddCreditsConflictingKey(t *testing.T) {
	s := openPostgresTestStore(t, time.Now)
	if err := s.AddCredits("dev-a", 10, "k1"); err != nil {
		t.Fatalf("first grant: %v", err)
	}
	if err := s.AddCredits("dev-b", 10, "k1"); err != errGrantConflict {
		t.Fatalf("reused key on a different device: err = %v, want errGrantConflict", err)
	}
	// Idempotent replay (same device + amount) is fine and does not double-credit.
	if err := s.AddCredits("dev-a", 10, "k1"); err != nil {
		t.Fatalf("idempotent replay: %v", err)
	}
	st, _ := s.State("dev-a")
	if st.Credits != 10 {
		t.Fatalf("credits = %d, want 10", st.Credits)
	}
}

// TestPostgresStore_NoDeadlockUnderMixedContention races Commit against DeleteAccount
// (and Reserve) on the same account — the exact opposing-lock-order cycle codex flagged
// (C1). With the store-wide quota-before-reservation lock order it must not deadlock.
func TestPostgresStore_NoDeadlockUnderMixedContention(t *testing.T) {
	s := openPostgresTestStore(t, time.Now)
	acct, _, err := s.UpsertIdentity("iss", "sub-stress", "", time.Now())
	if err != nil {
		t.Fatalf("upsert: %v", err)
	}
	if err := s.AddCredits(acct, maxGrant, "seed"); err != nil {
		t.Fatalf("seed: %v", err)
	}

	const iters = 60
	var wg sync.WaitGroup
	var deadlock atomic.Bool
	note := func(err error) {
		if err != nil && strings.Contains(err.Error(), "deadlock") {
			deadlock.Store(true)
		}
	}

	// Workers reserving + committing on the account's own device row.
	for w := 0; w < 4; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < iters; i++ {
				id, err := s.Reserve(acct)
				note(err)
				if err == nil {
					note(s.Commit(id))
				}
			}
		}()
	}
	// A racer repeatedly deleting the account (recreating quota rows are fine).
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < iters; i++ {
			if err := s.DeleteAccount(acct); err != nil && err != errAccountNotFound {
				note(err)
			}
		}
	}()
	wg.Wait()

	if deadlock.Load() {
		t.Fatal("a transaction deadlocked — lock order is not consistent")
	}
}

// TestPostgresStore_AccountAndDocLifecycle — account create/get, doc upsert bound to
// account existence, and delete cascading to docs + purging entitlements.
func TestPostgresStore_AccountAndDocLifecycle(t *testing.T) {
	s := openPostgresTestStore(t, time.Now)
	now := time.Now()

	acct, created, err := s.UpsertIdentity("iss", "sub", "e@x.com", now)
	if err != nil || !created {
		t.Fatalf("upsert: id=%q created=%v err=%v", acct, created, err)
	}
	if _, err := s.GetAccount(acct); err != nil {
		t.Fatalf("get account: %v", err)
	}
	if err := s.PutDoc(acct, "profile", `{"name":"하준"}`, now); err != nil {
		t.Fatalf("put doc: %v", err)
	}
	doc, ok, err := s.GetDoc(acct, "profile")
	if err != nil || !ok || doc != `{"name":"하준"}` {
		t.Fatalf("get doc: doc=%q ok=%v err=%v", doc, ok, err)
	}
	// Grant a credit, then delete — the account, its docs, and its entitlement must go.
	if err := s.AddCredits(acct, 10, "k-del"); err != nil {
		t.Fatalf("add credits: %v", err)
	}
	if err := s.DeleteAccount(acct); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := s.GetAccount(acct); err != errAccountNotFound {
		t.Fatalf("get after delete: %v, want errAccountNotFound", err)
	}
	if _, ok, _ := s.GetDoc(acct, "profile"); ok {
		t.Fatal("doc must be cascaded away on account delete")
	}
	if st, _ := s.State(acct); st.Credits != 0 {
		t.Fatalf("credits after delete = %d, want 0", st.Credits)
	}
	// A PutDoc for the now-deleted account must fail (FK), not resurrect data.
	if err := s.PutDoc(acct, "profile", `{}`, now); err == nil {
		t.Fatal("PutDoc for a deleted account should fail on the FK")
	}
}

// TestPostgresStore_NonceSingleUse — a nonce consumes once and only while unexpired.
func TestPostgresStore_NonceSingleUse(t *testing.T) {
	fc := &fakeClock{t: time.Date(2026, 7, 15, 0, 0, 0, 0, time.UTC)}
	s := openPostgresTestStore(t, fc.now)

	nonce, err := s.IssueNonce(fc.now())
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	ok, err := s.ConsumeNonce(nonce, fc.now())
	if err != nil || !ok {
		t.Fatalf("first consume: ok=%v err=%v", ok, err)
	}
	if ok, _ := s.ConsumeNonce(nonce, fc.now()); ok {
		t.Fatal("second consume must fail (single use)")
	}
	// An expired nonce does not validate.
	n2, _ := s.IssueNonce(fc.now())
	fc.advance(nonceTTL + time.Second)
	if ok, _ := s.ConsumeNonce(n2, fc.now()); ok {
		t.Fatal("expired nonce must not validate")
	}
}
