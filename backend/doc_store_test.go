package main

import (
	"testing"
	"time"
)

func TestDocStore_RoundTripKindsAndIsolation(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	for name, store := range authStores(t) {
		t.Run(name, func(t *testing.T) {
			a, _, _ := store.UpsertIdentity("iss", "subA", "", now)
			b, _, _ := store.UpsertIdentity("iss", "subB", "", now)

			if _, ok, err := store.GetDoc(a, docProfile); ok || err != nil {
				t.Fatalf("absent doc: ok=%v err=%v", ok, err)
			}
			if err := store.PutDoc(a, docProfile, `{"name":"하준"}`, now); err != nil {
				t.Fatal(err)
			}
			if doc, ok, _ := store.GetDoc(a, docProfile); !ok || doc != `{"name":"하준"}` {
				t.Fatalf("get after put: ok=%v doc=%q", ok, doc)
			}
			// Overwrite — arrival-order/last-write-wins.
			if err := store.PutDoc(a, docProfile, `{"name":"별"}`, now); err != nil {
				t.Fatal(err)
			}
			if doc, _, _ := store.GetDoc(a, docProfile); doc != `{"name":"별"}` {
				t.Fatalf("overwrite: doc=%q", doc)
			}
			// Distinct kinds don't collide.
			if err := store.PutDoc(a, docRoster, `["뽀삐"]`, now); err != nil {
				t.Fatal(err)
			}
			if d, _, _ := store.GetDoc(a, docProfile); d != `{"name":"별"}` {
				t.Fatalf("profile clobbered by roster: %q", d)
			}
			if d, _, _ := store.GetDoc(a, docRoster); d != `["뽀삐"]` {
				t.Fatalf("roster: %q", d)
			}
			// Accounts are isolated.
			if _, ok, _ := store.GetDoc(b, docProfile); ok {
				t.Fatal("account b sees account a's doc")
			}
		})
	}
}

func TestDocStore_PutRejectsUnknownAccount(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	for name, store := range authStores(t) {
		t.Run(name, func(t *testing.T) {
			// A PUT for a non-existent account must not create data (no orphan, no
			// resurrection after a delete race).
			if err := store.PutDoc("acct_ghost", docProfile, "x", now); err == nil {
				t.Fatal("PutDoc for unknown account succeeded, want error")
			}
		})
	}
}

func TestDocStore_DeleteAccountPurgesDocs(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	for name, store := range authStores(t) {
		t.Run(name, func(t *testing.T) {
			a, _, _ := store.UpsertIdentity("iss", "sub", "", now)
			_ = store.PutDoc(a, docProfile, "p", now)
			_ = store.PutDoc(a, docRoster, "r", now)

			if err := store.DeleteAccount(a); err != nil {
				t.Fatal(err)
			}
			if _, ok, _ := store.GetDoc(a, docProfile); ok {
				t.Fatal("profile survived account deletion")
			}
			if _, ok, _ := store.GetDoc(a, docRoster); ok {
				t.Fatal("roster survived account deletion")
			}
		})
	}
}
