package main

import (
	"bytes"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func sha256hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

// newAuthServer builds a server with auth enabled and its OIDC provider pointed at a
// test JWKS, with a fixed clock so signed tokens verify deterministically.
func newAuthServer(t *testing.T) (*server, *rsa.PrivateKey) {
	t.Helper()
	key := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	store := NewInMemoryQuotaStore()
	secret := strings.Repeat("k", 32)
	testProvider := func(name string) oidcProvider {
		return oidcProvider{name: name, issuer: "https://test.issuer", jwksURL: js.srv.URL, audiences: []string{"client-123"}}
	}
	srv := &server{
		cfg: config{
			sessionSecret: secret, quotaStore: "memory",
			appleClientID: "client-123", googleClientID: "client-123", kakaoClientID: "client-123",
		},
		accounts:      store,
		nonces:        store,
		quota:         store,
		docs:          store,
		sessionSecret: []byte(secret),
		jwks:          newJWKSCache(js.srv.Client()),
		apple:         testProvider("apple"),
		google:        testProvider("google"),
		kakao:         testProvider("kakao"),
		now:           func() time.Time { return testNow },
	}
	return srv, key
}

func getNonce(t *testing.T, srv *server) string {
	t.Helper()
	rec := httptest.NewRecorder()
	srv.handleAuthNonce(rec, httptest.NewRequest(http.MethodPost, "/v1/auth/nonce", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("nonce: code %d", rec.Code)
	}
	var body struct{ Nonce string }
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.Nonce == "" {
		t.Fatal("empty nonce")
	}
	return body.Nonce
}

// loginApple runs nonce → apple with a token for sub, returning the recorder.
func loginApple(t *testing.T, srv *server, key *rsa.PrivateKey, sub string) *httptest.ResponseRecorder {
	t.Helper()
	nonce := getNonce(t, srv)
	idt := signIDToken(t, key, "kid-1", map[string]any{"sub": sub, "nonce": sha256hex(nonce)})
	body, _ := json.Marshal(map[string]string{"idToken": idt, "nonce": nonce})
	rec := httptest.NewRecorder()
	srv.handleAppleAuth(rec, httptest.NewRequest(http.MethodPost, "/v1/auth/apple", bytes.NewReader(body)))
	return rec
}

func decodeLogin(t *testing.T, rec *httptest.ResponseRecorder) (token, accountID string, isNew bool) {
	t.Helper()
	var body struct {
		Token   string `json:"token"`
		Account struct {
			ID string `json:"id"`
		} `json:"account"`
		IsNew bool `json:"isNew"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode login: %v (body=%s)", err, rec.Body.String())
	}
	return body.Token, body.Account.ID, body.IsNew
}

func TestAuth_FullFlow(t *testing.T) {
	srv, key := newAuthServer(t)

	rec := loginApple(t, srv, key, "apple-sub-1")
	if rec.Code != http.StatusOK {
		t.Fatalf("login: code %d body=%s", rec.Code, rec.Body.String())
	}
	token, accountID, isNew := decodeLogin(t, rec)
	if token == "" || accountID == "" || !isNew {
		t.Fatalf("login result: token=%q account=%q isNew=%v", token, accountID, isNew)
	}

	// GET /v1/me with the session.
	meReq := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
	meReq.Header.Set("Authorization", "Bearer "+token)
	meRec := httptest.NewRecorder()
	srv.handleMe(meRec, meReq)
	if meRec.Code != http.StatusOK {
		t.Fatalf("me: code %d", meRec.Code)
	}
	var me struct{ ID string }
	_ = json.Unmarshal(meRec.Body.Bytes(), &me)
	if me.ID != accountID {
		t.Fatalf("me id = %q, want %q", me.ID, accountID)
	}

	// DELETE /v1/me revokes the account.
	delReq := httptest.NewRequest(http.MethodDelete, "/v1/me", nil)
	delReq.Header.Set("Authorization", "Bearer "+token)
	delRec := httptest.NewRecorder()
	srv.handleDeleteMe(delRec, delReq)
	if delRec.Code != http.StatusNoContent {
		t.Fatalf("delete: code %d", delRec.Code)
	}

	// The same session is now dead (account gone).
	me2 := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
	me2.Header.Set("Authorization", "Bearer "+token)
	me2Rec := httptest.NewRecorder()
	srv.handleMe(me2Rec, me2)
	if me2Rec.Code != http.StatusUnauthorized {
		t.Fatalf("me after delete = %d, want 401", me2Rec.Code)
	}
}

func TestAuth_SameIdentityReusesAccount(t *testing.T) {
	srv, key := newAuthServer(t)
	_, id1, new1 := decodeLogin(t, loginApple(t, srv, key, "apple-sub-1"))
	_, id2, new2 := decodeLogin(t, loginApple(t, srv, key, "apple-sub-1"))
	if !new1 || new2 || id1 != id2 {
		t.Fatalf("expected same account on re-login: id1=%q new1=%v id2=%q new2=%v", id1, new1, id2, new2)
	}
}

func TestAuth_NonceIsSingleUse(t *testing.T) {
	srv, key := newAuthServer(t)
	nonce := getNonce(t, srv)
	idt := signIDToken(t, key, "kid-1", map[string]any{"sub": "s", "nonce": sha256hex(nonce)})
	body, _ := json.Marshal(map[string]string{"idToken": idt, "nonce": nonce})

	for i, wantCode := range []int{http.StatusOK, http.StatusUnauthorized} {
		rec := httptest.NewRecorder()
		srv.handleAppleAuth(rec, httptest.NewRequest(http.MethodPost, "/v1/auth/apple", bytes.NewReader(body)))
		if rec.Code != wantCode {
			t.Fatalf("attempt %d: code %d, want %d (nonce must be single-use)", i, rec.Code, wantCode)
		}
	}
}

func TestAuth_NonceHashMustMatchToken(t *testing.T) {
	srv, key := newAuthServer(t)
	nonce := getNonce(t, srv)
	// Token carries the hash of a DIFFERENT nonce than the one presented.
	idt := signIDToken(t, key, "kid-1", map[string]any{"sub": "s", "nonce": sha256hex("some-other-nonce")})
	body, _ := json.Marshal(map[string]string{"idToken": idt, "nonce": nonce})
	rec := httptest.NewRecorder()
	srv.handleAppleAuth(rec, httptest.NewRequest(http.MethodPost, "/v1/auth/apple", bytes.NewReader(body)))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("mismatched nonce: code %d, want 401", rec.Code)
	}
}

func TestAuth_RejectsBadAudienceToken(t *testing.T) {
	srv, key := newAuthServer(t)
	nonce := getNonce(t, srv)
	idt := signIDToken(t, key, "kid-1", map[string]any{"sub": "s", "aud": "someone-else", "nonce": sha256hex(nonce)})
	body, _ := json.Marshal(map[string]string{"idToken": idt, "nonce": nonce})
	rec := httptest.NewRecorder()
	srv.handleAppleAuth(rec, httptest.NewRequest(http.MethodPost, "/v1/auth/apple", bytes.NewReader(body)))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("bad audience: code %d, want 401", rec.Code)
	}
}

func TestAuth_MissingBearerIs401(t *testing.T) {
	srv, _ := newAuthServer(t)
	rec := httptest.NewRecorder()
	srv.handleMe(rec, httptest.NewRequest(http.MethodGet, "/v1/me", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("no bearer: code %d, want 401", rec.Code)
	}
}

func TestAuth_DisabledWithoutSecret(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := &server{ // no session secret → auth disabled
		accounts: store, nonces: store, quota: store,
		now: func() time.Time { return testNow },
	}
	for _, h := range []struct {
		name string
		fn   func(http.ResponseWriter, *http.Request)
		req  *http.Request
	}{
		{"nonce", srv.handleAuthNonce, httptest.NewRequest(http.MethodPost, "/v1/auth/nonce", nil)},
		{"me", srv.handleMe, httptest.NewRequest(http.MethodGet, "/v1/me", nil)},
	} {
		rec := httptest.NewRecorder()
		h.fn(rec, h.req)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("%s with auth disabled: code %d, want 404", h.name, rec.Code)
		}
	}
}

func TestAuth_AppleDisabledWithoutClientID(t *testing.T) {
	srv, _ := newAuthServer(t)
	srv.cfg.appleClientID = "" // secret set, but Apple not configured
	rec := httptest.NewRecorder()
	body, _ := json.Marshal(map[string]string{"idToken": "x", "nonce": "y"})
	srv.handleAppleAuth(rec, httptest.NewRequest(http.MethodPost, "/v1/auth/apple", bytes.NewReader(body)))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("apple disabled: code %d, want 404", rec.Code)
	}
}
