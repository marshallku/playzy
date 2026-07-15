package main

import (
	"bytes"
	"crypto/rsa"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// The provider constructors pin each issuer's real OIDC coordinates.
func TestOIDCProviderConfig(t *testing.T) {
	g := googleProvider("g-aud")
	if g.issuer != "https://accounts.google.com" ||
		g.jwksURL != "https://www.googleapis.com/oauth2/v3/certs" ||
		len(g.audiences) != 1 || g.audiences[0] != "g-aud" {
		t.Fatalf("google provider misconfigured: %+v", g)
	}
	k := kakaoProvider("k-aud")
	if k.issuer != "https://kauth.kakao.com" ||
		k.jwksURL != "https://kauth.kakao.com/.well-known/jwks.json" ||
		len(k.audiences) != 1 || k.audiences[0] != "k-aud" {
		t.Fatalf("kakao provider misconfigured: %+v", k)
	}
}

// loginVia runs the nonce → provider-endpoint flow through a specific handler.
func loginVia(t *testing.T, srv *server, key *rsa.PrivateKey, sub string, handler http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()
	nonce := getNonce(t, srv)
	idt := signIDToken(t, key, "kid-1", map[string]any{"sub": sub, "nonce": sha256hex(nonce)})
	body, _ := json.Marshal(map[string]string{"idToken": idt, "nonce": nonce})
	rec := httptest.NewRecorder()
	handler(rec, httptest.NewRequest(http.MethodPost, "/v1/auth/provider", bytes.NewReader(body)))
	return rec
}

// Google and Kakao endpoints complete a login through the shared account path.
func TestGoogleAndKakaoLogin(t *testing.T) {
	cases := map[string]http.HandlerFunc{}
	srv, key := newAuthServer(t)
	cases["google"] = srv.handleGoogleAuth
	cases["kakao"] = srv.handleKakaoAuth

	for name, handler := range cases {
		t.Run(name, func(t *testing.T) {
			rec := loginVia(t, srv, key, "sub-"+name, handler)
			if rec.Code != http.StatusOK {
				t.Fatalf("%s login: code %d body=%s", name, rec.Code, rec.Body.String())
			}
			_, accountID, isNew := decodeLogin(t, rec)
			if accountID == "" || !isNew {
				t.Fatalf("%s login result: account=%q isNew=%v", name, accountID, isNew)
			}
		})
	}
}

// A provider with no configured client id is disabled (404).
func TestProviderDisabledWithoutClientID(t *testing.T) {
	srv, _ := newAuthServer(t)
	srv.cfg.googleClientID = ""
	srv.cfg.kakaoClientID = ""
	body, _ := json.Marshal(map[string]string{"idToken": "x", "nonce": "y"})
	for name, handler := range map[string]http.HandlerFunc{"google": srv.handleGoogleAuth, "kakao": srv.handleKakaoAuth} {
		rec := httptest.NewRecorder()
		handler(rec, httptest.NewRequest(http.MethodPost, "/x", bytes.NewReader(body)))
		if rec.Code != http.StatusNotFound {
			t.Fatalf("%s without client id: code %d, want 404", name, rec.Code)
		}
	}
}
