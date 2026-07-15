package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func quotaCredits(t *testing.T, rec *httptest.ResponseRecorder) int {
	t.Helper()
	var q struct {
		Credits int `json:"credits"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &q); err != nil {
		t.Fatalf("decode quota: %v (body=%s)", err, rec.Body.String())
	}
	return q.Credits
}

func getQuota(t *testing.T, srv *server, setHeaders func(*http.Request)) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/v1/quota", nil)
	setHeaders(req)
	rec := httptest.NewRecorder()
	srv.handleQuota(rec, req)
	return rec
}

// An authenticated request is scoped to the account; an anonymous one to its device.
func TestQuota_SubjectIsAccountWhenAuthedElseDevice(t *testing.T) {
	srv, key := newAuthServer(t)
	token, accountID, _ := decodeLogin(t, loginApple(t, srv, key, "sub-1"))

	if err := srv.quota.AddCredits(accountID, 5, "k-acct"); err != nil {
		t.Fatal(err)
	}
	if err := srv.quota.AddCredits("dev-1", 2, "k-dev"); err != nil {
		t.Fatal(err)
	}

	authed := getQuota(t, srv, func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+token) })
	if authed.Code != http.StatusOK || quotaCredits(t, authed) != 5 {
		t.Fatalf("authed quota: code=%d credits=%d, want 200/5", authed.Code, quotaCredits(t, authed))
	}
	anon := getQuota(t, srv, func(r *http.Request) { r.Header.Set(deviceHeader, "dev-1") })
	if anon.Code != http.StatusOK || quotaCredits(t, anon) != 2 {
		t.Fatalf("anon quota: code=%d credits=%d, want 200/2", anon.Code, quotaCredits(t, anon))
	}
}

// An anonymous caller can't present an account-shaped device id to reach an account.
func TestQuota_RejectsAccountPrefixedDeviceID(t *testing.T) {
	srv, _ := newAuthServer(t)
	rec := getQuota(t, srv, func(r *http.Request) { r.Header.Set(deviceHeader, accountIDPrefix+"deadbeef") })
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("acct-prefixed device id: code %d, want 400", rec.Code)
	}
}

// Any Authorization header is an auth attempt: a malformed/invalid one must 401,
// never silently fall back to device scope (even with X-Device-Id present).
func TestQuota_AnyAuthHeaderMustBeValid(t *testing.T) {
	srv, _ := newAuthServer(t)
	for _, authz := range []string{
		"Bearer not-a-real-session",
		"Bearer ",       // empty token
		"Bearer",        // no space — must not fall through to device scope
		"Basic dXNlcjpw", // wrong scheme
	} {
		rec := getQuota(t, srv, func(r *http.Request) {
			r.Header.Set("Authorization", authz)
			r.Header.Set(deviceHeader, "dev-1") // must NOT be used as a fallback
		})
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("authz=%q: code %d, want 401", authz, rec.Code)
		}
	}
}

// Deleting an account purges every row keyed by its subject: quota, credit grants,
// and reservations (Apple-mandated data removal).
func TestAccountStore_DeletePurgesEntitlements(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	for name, store := range authStores(t) {
		t.Run(name, func(t *testing.T) {
			id, _, _ := store.UpsertIdentity("https://appleid.apple.com", "sub", "", now)
			if err := store.AddCredits(id, 5, "grant-key"); err != nil {
				t.Fatal(err)
			}
			if _, err := store.Reserve(id); err != nil {
				t.Fatal(err)
			}

			if err := store.DeleteAccount(id); err != nil {
				t.Fatal(err)
			}

			st, _ := store.State(id)
			if st.Credits != 0 || st.FreeUsed != 0 {
				t.Fatalf("quota not purged after delete: %+v", st)
			}
			// The grant key is reusable now (grant history purged) — a reused key with a
			// different amount would otherwise conflict.
			if err := store.AddCredits(id, 3, "grant-key"); err != nil {
				t.Fatalf("credit_grant not purged (key still reserved): %v", err)
			}
		})
	}
}
