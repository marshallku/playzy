package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var testNow = time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)

func testKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func jwksJSON(kid string, pub *rsa.PublicKey) []byte {
	n := base64.RawURLEncoding.EncodeToString(pub.N.Bytes())
	e := base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes())
	doc := map[string]any{"keys": []map[string]string{
		{"kty": "RSA", "kid": kid, "use": "sig", "alg": "RS256", "n": n, "e": e},
	}}
	b, _ := json.Marshal(doc)
	return b
}

// jwksServer serves a JWKS for kid/pub, counts hits, and can be switched to fail.
type jwksServer struct {
	srv  *httptest.Server
	hits int32
	fail atomic.Bool
	body atomic.Value // []byte
}

func newJWKSServer(t *testing.T, kid string, pub *rsa.PublicKey) *jwksServer {
	t.Helper()
	js := &jwksServer{}
	js.body.Store(jwksJSON(kid, pub))
	js.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		atomic.AddInt32(&js.hits, 1)
		if js.fail.Load() {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		_, _ = w.Write(js.body.Load().([]byte))
	}))
	t.Cleanup(js.srv.Close)
	return js
}

func (js *jwksServer) provider(aud string) oidcProvider {
	return oidcProvider{name: "test", issuer: "https://test.issuer", jwksURL: js.srv.URL, audiences: []string{aud}}
}

// signIDToken builds an RS256 id_token with the given kid + claim overrides.
func signIDToken(t *testing.T, key *rsa.PrivateKey, kid string, over map[string]any) string {
	t.Helper()
	claims := jwt.MapClaims{
		"iss": "https://test.issuer",
		"aud": "client-123",
		"sub": "provider-subject-1",
		"iat": testNow.Add(-time.Minute).Unix(),
		"exp": testNow.Add(time.Hour).Unix(),
	}
	for k, v := range over {
		if v == nil {
			delete(claims, k)
		} else {
			claims[k] = v
		}
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tok.Header["kid"] = kid
	s, err := tok.SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func newCache() *jwksCache { return newJWKSCache(http.DefaultClient) }

func TestVerifyIDToken_Valid(t *testing.T) {
	key := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	c := newCache()

	raw := signIDToken(t, key, "kid-1", map[string]any{"email": "p@example.com"})
	claims, err := c.verifyIDToken(context.Background(), js.provider("client-123"), raw, testNow)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if claims.Subject != "provider-subject-1" || claims.Email != "p@example.com" {
		t.Fatalf("claims = %+v", claims)
	}
}

func TestVerifyIDToken_Rejections(t *testing.T) {
	key := testKey(t)
	other := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	c := newCache()
	p := js.provider("client-123")

	cases := map[string]string{
		"wrong audience": signIDToken(t, key, "kid-1", map[string]any{"aud": "someone-else"}),
		"wrong issuer":   signIDToken(t, key, "kid-1", map[string]any{"iss": "https://evil"}),
		"expired":        signIDToken(t, key, "kid-1", map[string]any{"exp": testNow.Add(-time.Hour).Unix()}),
		"missing exp":    signIDToken(t, key, "kid-1", map[string]any{"exp": nil}),
		"wrong key":      signIDToken(t, other, "kid-1", nil), // signed by a key not in JWKS
		"missing sub":    signIDToken(t, key, "kid-1", map[string]any{"sub": nil}),
		"empty sub":      signIDToken(t, key, "kid-1", map[string]any{"sub": ""}),
		"nonascii sub":   signIDToken(t, key, "kid-1", map[string]any{"sub": "숫자"}),
		"oversized sub":  signIDToken(t, key, "kid-1", map[string]any{"sub": strings.Repeat("a", maxDeviceIDLen+1)}),
	}
	for name, raw := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := c.verifyIDToken(context.Background(), p, raw, testNow); err == nil {
				t.Fatalf("%s: expected error, got nil", name)
			}
		})
	}
}

// The opaque subject is preserved verbatim (no canonicalization) so distinct
// provider identities never collapse.
func TestVerifyIDToken_SubjectPreservedVerbatim(t *testing.T) {
	key := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	c := newCache()
	raw := signIDToken(t, key, "kid-1", map[string]any{"sub": " spaced.subject "})
	claims, err := c.verifyIDToken(context.Background(), js.provider("client-123"), raw, testNow)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if claims.Subject != " spaced.subject " {
		t.Fatalf("subject canonicalized: %q", claims.Subject)
	}
}

// alg=none and HS256-confusion must both be rejected by the pinned valid-methods.
func TestVerifyIDToken_AlgorithmAttacks(t *testing.T) {
	key := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	c := newCache()
	p := js.provider("client-123")

	// alg=none, empty signature.
	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"none","typ":"JWT","kid":"kid-1"}`))
	payload := base64.RawURLEncoding.EncodeToString([]byte(`{"iss":"https://test.issuer","aud":"client-123","sub":"x","exp":9999999999}`))
	noneTok := header + "." + payload + "."
	if _, err := c.verifyIDToken(context.Background(), p, noneTok, testNow); err == nil {
		t.Fatal("alg=none accepted")
	}

	// HS256 signed with the RSA modulus as the shared secret (classic confusion).
	hs := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"iss": "https://test.issuer", "aud": "client-123", "sub": "x",
		"exp": testNow.Add(time.Hour).Unix(),
	})
	hs.Header["kid"] = "kid-1"
	hsTok, _ := hs.SignedString(key.PublicKey.N.Bytes())
	if _, err := c.verifyIDToken(context.Background(), p, hsTok, testNow); err == nil {
		t.Fatal("HS256 confusion accepted")
	}
}

// An unknown kid triggers exactly one refetch per minInterval, not a storm.
func TestJWKS_UnknownKidRateLimited(t *testing.T) {
	key := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	c := newCache()
	p := js.provider("client-123")

	// Prime the cache with a valid token (1 fetch).
	if _, err := c.verifyIDToken(context.Background(), p, signIDToken(t, key, "kid-1", nil), testNow); err != nil {
		t.Fatal(err)
	}
	base := atomic.LoadInt32(&js.hits)

	// Two tokens with an unknown kid within the interval → at most one extra fetch.
	unknown := signIDToken(t, key, "kid-unknown", nil)
	_, _ = c.verifyIDToken(context.Background(), p, unknown, testNow.Add(time.Second))
	_, _ = c.verifyIDToken(context.Background(), p, unknown, testNow.Add(2*time.Second))
	if extra := atomic.LoadInt32(&js.hits) - base; extra > 1 {
		t.Fatalf("unknown kid caused %d fetches within interval, want ≤1", extra)
	}
}

// A key rotation (new kid) is picked up once the min interval elapses.
func TestJWKS_RotationPickedUp(t *testing.T) {
	key := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	c := newCache()
	p := js.provider("client-123")

	if _, err := c.verifyIDToken(context.Background(), p, signIDToken(t, key, "kid-1", nil), testNow); err != nil {
		t.Fatal(err)
	}
	// Rotate: server now serves kid-2 for a new key.
	key2 := testKey(t)
	js.body.Store(jwksJSON("kid-2", &key2.PublicKey))

	raw := signIDToken(t, key2, "kid-2", nil)
	// Before the interval elapses, the new kid isn't fetched → fails.
	if _, err := c.verifyIDToken(context.Background(), p, raw, testNow.Add(30*time.Second)); err == nil {
		t.Fatal("rotation fetched before min interval")
	}
	// After the interval, the refetch lands the new key.
	if _, err := c.verifyIDToken(context.Background(), p, raw, testNow.Add(61*time.Second)); err != nil {
		t.Fatalf("rotation not picked up after interval: %v", err)
	}
}

// A failed JWKS refresh keeps the existing cached keys (rotation/DoS-safe).
func TestJWKS_FailedRefreshKeepsOldKeys(t *testing.T) {
	key := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	c := newCache()
	p := js.provider("client-123")

	if _, err := c.verifyIDToken(context.Background(), p, signIDToken(t, key, "kid-1", nil), testNow); err != nil {
		t.Fatal(err)
	}
	js.fail.Store(true) // all further fetches error

	// A token with the still-cached kid keeps verifying despite the outage.
	if _, err := c.verifyIDToken(context.Background(), p, signIDToken(t, key, "kid-1", nil), testNow.Add(2*time.Minute)); err != nil {
		t.Fatalf("cached key lost on refresh failure: %v", err)
	}
}

// After the TTL, a known kid is re-fetched and a provider-retired key stops being
// trusted (codex review C1).
func TestJWKS_StaleKeyRetiredAfterTTL(t *testing.T) {
	key := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	c := newCache()
	p := js.provider("client-123")

	old := signIDToken(t, key, "kid-1", nil)
	if _, err := c.verifyIDToken(context.Background(), p, old, testNow); err != nil {
		t.Fatal(err)
	}
	// Provider retires kid-1, now publishing only kid-2.
	key2 := testKey(t)
	js.body.Store(jwksJSON("kid-2", &key2.PublicKey))

	// Past the TTL, a fresh verify of a kid-1 token forces a refresh that drops kid-1.
	if _, err := c.verifyIDToken(context.Background(), p, old, testNow.Add(2*time.Hour)); err == nil {
		t.Fatal("retired key still trusted after TTL refresh")
	}
	// The current key still works (give the token an exp beyond the verify time).
	current := signIDToken(t, key2, "kid-2", map[string]any{"exp": testNow.Add(3 * time.Hour).Unix()})
	if _, err := c.verifyIDToken(context.Background(), p, current, testNow.Add(2*time.Hour+time.Second)); err != nil {
		t.Fatalf("current key rejected: %v", err)
	}
}

// A provider may accept more than one iss form (Google's HTTPS + legacy bare
// domain); both verify, and the claims carry the CANONICAL issuer so one user is
// one account. An unrelated issuer is still rejected.
func TestVerifyIDToken_MultipleAcceptedIssuers(t *testing.T) {
	key := testKey(t)
	js := newJWKSServer(t, "kid-1", &key.PublicKey)
	c := newCache()
	p := oidcProvider{
		name:            "google",
		issuer:          "https://accounts.google.com",
		acceptedIssuers: []string{"https://accounts.google.com", "accounts.google.com"},
		jwksURL:         js.srv.URL,
		audiences:       []string{"client-123"},
	}

	for _, iss := range []string{"https://accounts.google.com", "accounts.google.com"} {
		raw := signIDToken(t, key, "kid-1", map[string]any{"iss": iss})
		claims, err := c.verifyIDToken(context.Background(), p, raw, testNow)
		if err != nil {
			t.Fatalf("iss=%q rejected: %v", iss, err)
		}
		if claims.Issuer != "https://accounts.google.com" {
			t.Fatalf("iss=%q: claims issuer = %q, want canonical", iss, claims.Issuer)
		}
	}

	bad := signIDToken(t, key, "kid-1", map[string]any{"iss": "https://evil.example"})
	if _, err := c.verifyIDToken(context.Background(), p, bad, testNow); err == nil {
		t.Fatal("unrelated issuer accepted")
	}
}

func TestSession_RoundTrip(t *testing.T) {
	secret := []byte(strings.Repeat("s", 32))
	tok, err := issueSession(secret, "acct-1", 3, testNow)
	if err != nil {
		t.Fatal(err)
	}
	acct, ver, err := parseSession(secret, tok, testNow.Add(24*time.Hour))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if acct != "acct-1" || ver != 3 {
		t.Fatalf("acct=%q ver=%d", acct, ver)
	}
}

func TestSession_Rejections(t *testing.T) {
	secret := []byte(strings.Repeat("s", 32))
	tok, _ := issueSession(secret, "acct-1", 0, testNow)

	// Expired.
	if _, _, err := parseSession(secret, tok, testNow.Add(sessionTTL+time.Hour)); err == nil {
		t.Fatal("expired session accepted")
	}
	// Wrong secret.
	if _, _, err := parseSession([]byte(strings.Repeat("x", 32)), tok, testNow); err == nil {
		t.Fatal("session accepted under wrong secret")
	}
	// alg=none session rejected (HS256 pinned).
	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"none","typ":"JWT"}`))
	payload := base64.RawURLEncoding.EncodeToString([]byte(`{"sub":"acct-1","exp":9999999999}`))
	if _, _, err := parseSession(secret, header+"."+payload+".", testNow); err == nil {
		t.Fatal("alg=none session accepted")
	}
}

// A session with a missing / non-integer / negative ver must be rejected rather than
// coerced to 0, which would defeat token-version revocation (codex review C2).
func TestSession_RequiresValidVer(t *testing.T) {
	secret := []byte(strings.Repeat("s", 32))
	sign := func(ver any) string {
		claims := jwt.MapClaims{"sub": "acct-1", "iat": testNow.Unix(), "exp": testNow.Add(time.Hour).Unix()}
		if ver != nil {
			claims["ver"] = ver
		}
		s, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(secret)
		return s
	}
	for name, tok := range map[string]string{
		"missing ver":    sign(nil),
		"fractional ver": sign(1.5),
		"negative ver":   sign(-1),
	} {
		if _, _, err := parseSession(secret, tok, testNow); err == nil {
			t.Fatalf("%s: accepted, want rejected", name)
		}
	}
	// A valid non-negative integer ver is accepted.
	if _, ver, err := parseSession(secret, sign(0), testNow); err != nil || ver != 0 {
		t.Fatalf("ver=0 rejected: ver=%d err=%v", ver, err)
	}
}

func TestNonceHashMatches(t *testing.T) {
	// sha256("abc") hex.
	const raw = "abc"
	const hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	if !nonceHashMatches(raw, hash) {
		t.Fatal("correct nonce hash rejected")
	}
	if !nonceHashMatches(raw, strings.ToUpper(hash)) {
		t.Fatal("uppercase nonce hash rejected (should be case-insensitive)")
	}
	if nonceHashMatches(raw, "deadbeef") {
		t.Fatal("wrong nonce hash accepted")
	}
}

func TestValidateSessionSecret(t *testing.T) {
	if err := validateSessionSecret(strings.Repeat("s", 31)); err == nil {
		t.Fatal("31-byte secret accepted")
	}
	if err := validateSessionSecret(strings.Repeat("s", 32)); err != nil {
		t.Fatalf("32-byte secret rejected: %v", err)
	}
}
