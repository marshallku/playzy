package main

import (
	"errors"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// fakeClock is a manually-advanced clock for deterministic TTL/expiry tests.
type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *fakeClock) now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *fakeClock) advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

// bothStores runs a subtest against each QuotaStore implementation so the
// reservation lifecycle is verified identically for the in-memory and durable
// backends. Each store gets its own fresh fakeClock.
func bothStores(t *testing.T, fn func(t *testing.T, s QuotaStore, fc *fakeClock)) {
	t.Helper()
	base := time.Date(2026, 7, 14, 12, 0, 0, 0, time.UTC)

	t.Run("memory", func(t *testing.T) {
		fc := &fakeClock{t: base}
		fn(t, newInMemoryQuotaStoreClock(fc.now), fc)
	})
	t.Run("sqlite", func(t *testing.T) {
		fc := &fakeClock{t: base}
		s, err := openSQLiteQuotaStoreClock(filepath.Join(t.TempDir(), "q.db"), fc.now)
		if err != nil {
			t.Fatalf("open sqlite: %v", err)
		}
		t.Cleanup(func() { _ = s.Close() })
		fn(t, s, fc)
	})
	// The durable prod store (k3s) — only when a test Postgres is configured
	// (PLAYZY_TEST_DATABASE_URL); skipped otherwise so the suite stays green without one.
	t.Run("postgres", func(t *testing.T) {
		fc := &fakeClock{t: base}
		fn(t, openPostgresTestStore(t, fc.now), fc)
	})
}

func TestQuotaStore_FreeThenCreditsThenExceeded(t *testing.T) {
	bothStores(t, func(t *testing.T, s QuotaStore, _ *fakeClock) {
		for i := 0; i < freeStoryLimit; i++ {
			if err := reserveCommit(t, s, "d"); err != nil {
				t.Fatalf("free reserve %d: %v", i, err)
			}
		}
		if _, err := s.Reserve("d"); !errors.Is(err, errQuotaExceeded) {
			t.Fatalf("expected quota exceeded, got %v", err)
		}
		if err := s.AddCredits("d", 2, "k"); err != nil {
			t.Fatalf("AddCredits: %v", err)
		}
		if err := reserveCommit(t, s, "d"); err != nil {
			t.Fatalf("credit reserve: %v", err)
		}
		st := mustState(t, s, "d")
		if st.Credits != 1 || st.FreeUsed != freeStoryLimit {
			t.Fatalf("state = %+v", st)
		}
	})
}

func TestQuotaStore_CommitConsumes_ReleaseFrees(t *testing.T) {
	bothStores(t, func(t *testing.T, s QuotaStore, _ *fakeClock) {
		// A bare hold does not consume committed quota…
		id, err := s.Reserve("d")
		if err != nil {
			t.Fatalf("reserve: %v", err)
		}
		if u := mustState(t, s, "d").FreeUsed; u != 0 {
			t.Fatalf("hold consumed committed quota early: freeUsed = %d", u)
		}
		// …releasing it frees the slot for reuse.
		s.Release(id)
		for i := 0; i < freeStoryLimit; i++ {
			if err := reserveCommit(t, s, "d"); err != nil {
				t.Fatalf("post-release reserve %d: %v", i, err)
			}
		}
		if u := mustState(t, s, "d").FreeUsed; u != freeStoryLimit {
			t.Fatalf("freeUsed = %d after 3 commits", u)
		}
	})
}

func TestQuotaStore_PendingHoldsBlockAvailability(t *testing.T) {
	bothStores(t, func(t *testing.T, s QuotaStore, _ *fakeClock) {
		// Reserving the whole free tier as un-committed holds still blocks further
		// reservations — concurrent in-flight generations can't over-spend.
		for i := 0; i < freeStoryLimit; i++ {
			if _, err := s.Reserve("d"); err != nil {
				t.Fatalf("hold %d: %v", i, err)
			}
		}
		if _, err := s.Reserve("d"); !errors.Is(err, errQuotaExceeded) {
			t.Fatalf("holds did not block availability, got %v", err)
		}
	})
}

func TestQuotaStore_AbandonedHoldExpiresAfterTTL(t *testing.T) {
	bothStores(t, func(t *testing.T, s QuotaStore, fc *fakeClock) {
		// A hold that is never committed/released (crash/abandon) must not
		// permanently consume the allowance — it expires after the TTL.
		if _, err := s.Reserve("d"); err != nil {
			t.Fatalf("reserve: %v", err)
		}
		fc.advance(reservationTTL + time.Minute)
		for i := 0; i < freeStoryLimit; i++ {
			if err := reserveCommit(t, s, "d"); err != nil {
				t.Fatalf("post-expiry reserve %d: %v", i, err)
			}
		}
	})
}

func TestQuotaStore_AddCreditsIdempotency(t *testing.T) {
	bothStores(t, func(t *testing.T, s QuotaStore, _ *fakeClock) {
		if err := s.AddCredits("d", 5, "p1"); err != nil {
			t.Fatalf("grant: %v", err)
		}
		// Same (key, device, amount) replays are no-ops.
		if err := s.AddCredits("d", 5, "p1"); err != nil {
			t.Fatalf("idempotent replay: %v", err)
		}
		if c := mustState(t, s, "d").Credits; c != 5 {
			t.Fatalf("credits = %d, want 5 (idempotent)", c)
		}
		// Same key, different amount → conflict, no grant applied.
		if err := s.AddCredits("d", 9, "p1"); !errors.Is(err, errGrantConflict) {
			t.Fatalf("expected grant conflict, got %v", err)
		}
		if c := mustState(t, s, "d").Credits; c != 5 {
			t.Fatalf("credits = %d after conflict, want 5", c)
		}
		// A different key stacks.
		if err := s.AddCredits("d", 3, "p2"); err != nil {
			t.Fatalf("second grant: %v", err)
		}
		if c := mustState(t, s, "d").Credits; c != 8 {
			t.Fatalf("credits = %d, want 8", c)
		}
		// Out-of-range amounts are rejected.
		if err := s.AddCredits("d", 0, "p3"); err == nil {
			t.Fatal("zero amount must be rejected")
		}
		if err := s.AddCredits("d", maxGrant+1, "p4"); err == nil {
			t.Fatal("over-cap amount must be rejected")
		}
	})
}

func TestQuotaStore_StateOnUnknownDeviceIsZero(t *testing.T) {
	bothStores(t, func(t *testing.T, s QuotaStore, _ *fakeClock) {
		st := mustState(t, s, "never-seen")
		if st.FreeUsed != 0 || st.Credits != 0 || st.FreeLimit != freeStoryLimit || !st.CanGenerate {
			t.Fatalf("unknown device state = %+v", st)
		}
	})
}

func TestQuotaStore_ConcurrentReserveNeverOverGrants(t *testing.T) {
	bothStores(t, func(t *testing.T, s QuotaStore, _ *fakeClock) {
		if err := s.AddCredits("d", 4, "k"); err != nil {
			t.Fatalf("grant: %v", err)
		}
		const workers = 32
		limit := freeStoryLimit + 4 // free tier + granted credits
		var granted int64
		var wg sync.WaitGroup
		for i := 0; i < workers; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				id, err := s.Reserve("d")
				if errors.Is(err, errQuotaExceeded) {
					return
				}
				if err != nil {
					return
				}
				if err := s.Commit(id); err == nil {
					atomic.AddInt64(&granted, 1)
				}
			}()
		}
		wg.Wait()
		if granted != int64(limit) {
			t.Fatalf("granted %d, want exactly %d (over/under-grant)", granted, limit)
		}
	})
}

// ---- SQLite-specific (durability / migration / defensive guards) ----------

func TestSQLiteQuotaStore_SurvivesReopen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "q.db")
	fc := &fakeClock{t: time.Date(2026, 7, 14, 12, 0, 0, 0, time.UTC)}

	s1, err := openSQLiteQuotaStoreClock(path, fc.now)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if err := reserveCommit(t, s1, "d"); err != nil {
		t.Fatalf("reserve/commit: %v", err)
	}
	if err := s1.AddCredits("d", 7, "k"); err != nil {
		t.Fatalf("grant: %v", err)
	}
	if err := s1.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	// Reopen the same file: committed quota + credits must still be there.
	s2, err := openSQLiteQuotaStoreClock(path, fc.now)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	t.Cleanup(func() { _ = s2.Close() })
	st := mustState(t, s2, "d")
	if st.FreeUsed != 1 || st.Credits != 7 {
		t.Fatalf("state after reopen = %+v", st)
	}
	// The idempotency key also survives — a redelivered grant must not double.
	if err := s2.AddCredits("d", 7, "k"); err != nil {
		t.Fatalf("idempotent grant after reopen: %v", err)
	}
	if c := mustState(t, s2, "d").Credits; c != 7 {
		t.Fatalf("credits = %d after reopen replay, want 7", c)
	}
}

func TestSQLiteQuotaStore_StateCreatesNoRow(t *testing.T) {
	s, err := openSQLiteQuotaStoreClock(filepath.Join(t.TempDir(), "q.db"), time.Now)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { _ = s.Close() })

	// A read for an unknown device must not durably write a row (an unauthenticated
	// GET /v1/quota must not let arbitrary ids grow the store).
	_ = mustState(t, s, "attacker")
	var rows int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM quota`).Scan(&rows); err != nil {
		t.Fatalf("count: %v", err)
	}
	if rows != 0 {
		t.Fatalf("State created %d rows, want 0", rows)
	}
}

func TestSQLiteQuotaStore_CommitCreditUnderflowStaysNonNegative(t *testing.T) {
	s, err := openSQLiteQuotaStoreClock(filepath.Join(t.TempDir(), "q.db"), time.Now)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { _ = s.Close() })

	// Construct a pathological state directly: a credit hold whose allowance is
	// already gone. Committing it must not drive credits negative.
	if _, err := s.db.Exec(`INSERT INTO quota(device_id, free_used, credits) VALUES('d', 3, 0)`); err != nil {
		t.Fatalf("seed quota: %v", err)
	}
	if _, err := s.db.Exec(`INSERT INTO reservation(id, device_id, source, created_at) VALUES('r','d','credit',0)`); err != nil {
		t.Fatalf("seed reservation: %v", err)
	}
	if err := s.Commit("r"); !errors.Is(err, errCreditUnderflow) {
		t.Fatalf("commit = %v, want errCreditUnderflow", err)
	}
	if c := mustState(t, s, "d").Credits; c != 0 {
		t.Fatalf("credits = %d, want 0 (never negative)", c)
	}
	// The invalid hold is dropped.
	var rows int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM reservation WHERE id='r'`).Scan(&rows); err != nil {
		t.Fatalf("count: %v", err)
	}
	if rows != 0 {
		t.Fatal("underflow hold was not dropped")
	}
}

func TestMigrate_RejectsNewerSchema(t *testing.T) {
	s, err := openSQLiteQuotaStoreClock(filepath.Join(t.TempDir(), "q.db"), time.Now)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	// Simulate a database written by a newer binary.
	if _, err := s.db.Exec(`PRAGMA user_version = 999`); err != nil {
		t.Fatalf("bump version: %v", err)
	}
	if err := migrate(s.db); err == nil {
		t.Fatal("migrate must reject a schema newer than the binary")
	}
	_ = s.Close()
}

func TestMigrate_IsIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "q.db")
	s, err := openSQLiteQuotaStoreClock(path, time.Now)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	// Running migrate again on an already-migrated db is a no-op, not an error.
	if err := migrate(s.db); err != nil {
		t.Fatalf("re-migrate: %v", err)
	}
	var version int
	if err := s.db.QueryRow(`PRAGMA user_version`).Scan(&version); err != nil {
		t.Fatalf("version: %v", err)
	}
	if version != len(migrations) {
		t.Fatalf("user_version = %d, want %d", version, len(migrations))
	}
	_ = s.Close()
}
