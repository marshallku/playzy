package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestProfileRosterSync(t *testing.T) {
	srv, key := newAuthServer(t)
	mux := newMux(srv)
	token, _, _ := decodeLogin(t, loginApple(t, srv, key, "sub-1"))

	do := func(method, path, body, auth string) *httptest.ResponseRecorder {
		var r *http.Request
		if body == "" {
			r = httptest.NewRequest(method, path, nil)
		} else {
			r = httptest.NewRequest(method, path, strings.NewReader(body))
		}
		if auth != "" {
			r.Header.Set("Authorization", "Bearer "+auth)
		}
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, r)
		return rec
	}
	putBody := func(doc string) string {
		b, _ := json.Marshal(map[string]any{"doc": doc})
		return string(b)
	}

	// Absent → doc null.
	rec := do(http.MethodGet, "/v1/profile", "", token)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"doc":null`) {
		t.Fatalf("absent profile: code=%d body=%s", rec.Code, rec.Body.String())
	}

	// PUT then GET round-trips the opaque doc.
	const profile = `{"givenName":"하준","ageBand":"toddler"}`
	if rec := do(http.MethodPut, "/v1/profile", putBody(profile), token); rec.Code != http.StatusNoContent {
		t.Fatalf("put profile: code=%d body=%s", rec.Code, rec.Body.String())
	}
	rec = do(http.MethodGet, "/v1/profile", "", token)
	var got struct{ Doc string }
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if got.Doc != profile {
		t.Fatalf("get profile doc=%q, want %q", got.Doc, profile)
	}

	// Roster is a separate document.
	if rec := do(http.MethodPut, "/v1/roster", putBody(`["뽀삐"]`), token); rec.Code != http.StatusNoContent {
		t.Fatalf("put roster: code=%d", rec.Code)
	}
	rec = do(http.MethodGet, "/v1/roster", "", token)
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if got.Doc != `["뽀삐"]` {
		t.Fatalf("roster doc=%q", got.Doc)
	}

	// No/invalid bearer → 401.
	if rec := do(http.MethodGet, "/v1/profile", "", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("no bearer: code=%d", rec.Code)
	}

	// A different account sees its OWN (absent) profile, not sub-1's.
	other, _, _ := decodeLogin(t, loginApple(t, srv, key, "sub-2"))
	rec = do(http.MethodGet, "/v1/profile", "", other)
	if !strings.Contains(rec.Body.String(), `"doc":null`) {
		t.Fatalf("account isolation broken: sub-2 sees %s", rec.Body.String())
	}
}

func TestProfilePut_Validation(t *testing.T) {
	srv, key := newAuthServer(t)
	mux := newMux(srv)
	token, _, _ := decodeLogin(t, loginApple(t, srv, key, "sub-1"))

	post := func(body []byte) int {
		r := httptest.NewRequest(http.MethodPut, "/v1/profile", bytes.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, r)
		return rec.Code
	}

	// Missing doc / null doc / wrong type → 400.
	for _, body := range []string{`{}`, `{"doc":null}`, `{"doc":123}`} {
		if code := post([]byte(body)); code != http.StatusBadRequest {
			t.Fatalf("body %s: code=%d, want 400", body, code)
		}
	}
	// Malformed UTF-8 in the body → 400 (not silently normalized + stored).
	malformed := append(append([]byte(`{"doc":"`), 0xff), []byte(`"}`)...)
	if code := post(malformed); code != http.StatusBadRequest {
		t.Fatalf("malformed utf-8: code=%d, want 400", code)
	}
	// Oversized doc → 413.
	big, _ := json.Marshal(map[string]any{"doc": strings.Repeat("a", maxDocBytes+1)})
	if code := post(big); code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized: code=%d, want 413", code)
	}
	// At the cap → 204.
	ok, _ := json.Marshal(map[string]any{"doc": strings.Repeat("a", maxDocBytes)})
	if code := post(ok); code != http.StatusNoContent {
		t.Fatalf("at cap: code=%d, want 204", code)
	}
	// A cap-sized doc of control bytes (each a 6-char \uXXXX escape → ~6× body) must
	// still fit the body limit and succeed.
	ctrl, _ := json.Marshal(map[string]any{"doc": strings.Repeat("\x01", maxDocBytes)})
	if code := post(ctrl); code != http.StatusNoContent {
		t.Fatalf("control-byte doc at cap: code=%d, want 204", code)
	}
}

func TestProfileDisabledWithoutAuth(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := &server{quota: store, accounts: store, nonces: store, docs: store} // no session secret
	mux := newMux(srv)
	r := httptest.NewRequest(http.MethodGet, "/v1/profile", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, r)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("auth disabled: code=%d, want 404", rec.Code)
	}
}
