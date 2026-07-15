package main

import (
	"context"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Auth core (WU3): verify a provider's OIDC id_token, then mint our own session
// JWT. All of Apple / Google / Kakao expose an id_token, so one generic verifier
// serves them — only the provider config differs (WU3b adds Google/Kakao). The
// account store + HTTP handlers that use these live in later commits.

// sessionTTL bounds a stateless session. Revocation does not rely on this alone:
// requireAccount re-checks account existence + token version on every request, so a
// deleted/rotated account invalidates its sessions immediately (codex plan C2).
const sessionTTL = 30 * 24 * time.Hour

// minSessionSecretLen is 256 bits — below this an HS256 session is brute-forceable
// and thus forgeable, so we fail startup rather than mint weak sessions (codex C5).
const minSessionSecretLen = 32

var (
	errNoKey        = errors.New("no signing key for token kid")
	errBadIssuer    = errors.New("token issuer not accepted")
	errBadAudience  = errors.New("token audience not accepted")
	errBadSubject   = errors.New("token subject missing or malformed")
	errWeakSecret   = fmt.Errorf("PLAYZY_SESSION_SECRET must be at least %d bytes", minSessionSecretLen)
	errBadSession   = errors.New("invalid session")
)

// validateSessionSecret enforces sufficient key material when auth is configured.
func validateSessionSecret(secret string) error {
	if len(secret) < minSessionSecretLen {
		return errWeakSecret
	}
	return nil
}

// oidcProvider is a verifiable OIDC issuer. issuer is the CANONICAL issuer used for
// account identity keying; acceptedIssuers is the set of `iss` values a token may
// legitimately carry (⊇ {issuer}) — some providers (Google) mint more than one form.
// When acceptedIssuers is empty it defaults to {issuer}. audiences is the set of
// accepted `aud` values (our client ids at that provider).
type oidcProvider struct {
	name            string
	issuer          string
	acceptedIssuers []string
	jwksURL         string
	audiences       []string
}

func appleProvider(clientID string) oidcProvider {
	return oidcProvider{
		name:      "apple",
		issuer:    "https://appleid.apple.com",
		jwksURL:   "https://appleid.apple.com/auth/keys",
		audiences: []string{clientID},
	}
}

func googleProvider(clientID string) oidcProvider {
	return oidcProvider{
		name:   "google",
		issuer: "https://accounts.google.com",
		// Google issues both the HTTPS and the legacy bare-domain form; accept both
		// but key accounts on the canonical `issuer` above so one user stays one account.
		acceptedIssuers: []string{"https://accounts.google.com", "accounts.google.com"},
		jwksURL:         "https://www.googleapis.com/oauth2/v3/certs",
		audiences:       []string{clientID},
	}
}

func kakaoProvider(clientID string) oidcProvider {
	return oidcProvider{
		name:      "kakao",
		issuer:    "https://kauth.kakao.com",
		jwksURL:   "https://kauth.kakao.com/.well-known/jwks.json",
		audiences: []string{clientID},
	}
}

// issuerAccepted reports whether the token's iss is valid for p. Defaults to the
// canonical issuer when no explicit accepted set is configured.
func (p oidcProvider) issuerAccepted(iss string) bool {
	allowed := p.acceptedIssuers
	if len(allowed) == 0 {
		allowed = []string{p.issuer}
	}
	for _, a := range allowed {
		if iss == a {
			return true
		}
	}
	return false
}

// idClaims are the verified fields we consume from an id_token.
type idClaims struct {
	Issuer  string
	Subject string
	Email   string
	Nonce   string // provider stores sha256(rawNonce), hex — see nonceHashMatches
}

// jwksCache fetches and caches issuers' JWKS. It is rotation-safe and DoS-safe
// (codex plan C4): fetches for one URL are coalesced, retried at most once per
// minInterval regardless of outcome, and a failed refresh keeps the existing keys.
type jwksCache struct {
	client      *http.Client
	minInterval time.Duration // floor between fetch attempts per URL (DoS guard)
	ttl         time.Duration // after this, a cached key set is refreshed even if the kid is known
	maxBody     int64

	mu      sync.Mutex
	entries map[string]*jwksEntry
}

type jwksEntry struct {
	fetchMu     sync.Mutex // serializes (coalesces) fetches for this URL
	keys        map[string]*rsa.PublicKey
	refreshedAt time.Time // last SUCCESSFUL fetch — drives the TTL
	lastAttempt time.Time // last fetch attempt (success or fail) — drives the rate limit
}

func newJWKSCache(client *http.Client) *jwksCache {
	return &jwksCache{
		client:      client,
		minInterval: 60 * time.Second,
		ttl:         time.Hour,
		maxBody:     1 << 20, // 1 MiB — a JWKS is small; bound a hostile response
		entries:     map[string]*jwksEntry{},
	}
}

func (c *jwksCache) entryFor(url string) *jwksEntry {
	c.mu.Lock()
	defer c.mu.Unlock()
	e := c.entries[url]
	if e == nil {
		e = &jwksEntry{keys: map[string]*rsa.PublicKey{}}
		c.entries[url] = e
	}
	return e
}

// keyForKid returns the RSA public key for kid at jwksURL, refetching once (and
// only once per minInterval) if the kid isn't cached. now is injectable for tests.
func (c *jwksCache) keyForKid(ctx context.Context, jwksURL, kid string, now time.Time) (*rsa.PublicKey, error) {
	e := c.entryFor(jwksURL)

	e.fetchMu.Lock()
	defer e.fetchMu.Unlock()

	// A cached key is trusted only while the set is fresh: after ttl we refresh even
	// for a known kid, so a provider-retired or compromised key stops being trusted
	// (codex review C1). A missing kid also triggers a refresh (rotation).
	cached := e.lookup(kid)
	fresh := !e.refreshedAt.IsZero() && now.Sub(e.refreshedAt) < c.ttl
	if cached != nil && fresh {
		return cached, nil
	}

	// Rate-limit attempts (per URL) so a flood of unknown kids can't cause a fetch
	// storm; a legitimate rotation / TTL refresh proceeds once the interval elapses.
	if !e.lastAttempt.IsZero() && now.Sub(e.lastAttempt) < c.minInterval {
		if cached != nil {
			return cached, nil // rate-limited: serve the (stale) cached key for availability
		}
		return nil, errNoKey
	}
	e.lastAttempt = now

	fetched, err := c.fetch(ctx, jwksURL)
	if err != nil {
		// Keep the existing keys on a failed refresh (availability / rotation-safe).
		if cached != nil {
			return cached, nil
		}
		return nil, err
	}
	// Replace (not merge): trust exactly the currently-published key set, so a
	// retired/compromised kid is dropped once the provider stops publishing it
	// (codex review C1). Rotation overlap stays safe because the provider publishes
	// both the old and new kid in the JWKS during the overlap window, so this fetch
	// captures both; a kid is only dropped after the provider itself retires it.
	e.keys = fetched
	e.refreshedAt = now

	if k := e.lookup(kid); k != nil {
		return k, nil
	}
	return nil, errNoKey
}

// lookup reads a cached key. Callers hold fetchMu, under which keys is mutated.
func (e *jwksEntry) lookup(kid string) *rsa.PublicKey {
	return e.keys[kid]
}

// fetch downloads and parses a JWKS document into kid→RSA-public-key.
func (c *jwksCache) fetch(ctx context.Context, jwksURL string) (map[string]*rsa.PublicKey, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, jwksURL, nil)
	if err != nil {
		return nil, err
	}
	res, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("jwks %s: status %d", jwksURL, res.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(res.Body, c.maxBody))
	if err != nil {
		return nil, err
	}
	return parseJWKS(raw)
}

type jwksDoc struct {
	Keys []struct {
		Kty string `json:"kty"`
		Kid string `json:"kid"`
		Use string `json:"use"`
		Alg string `json:"alg"`
		N   string `json:"n"`
		E   string `json:"e"`
	} `json:"keys"`
}

func parseJWKS(raw []byte) (map[string]*rsa.PublicKey, error) {
	var doc jwksDoc
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, fmt.Errorf("jwks parse: %w", err)
	}
	out := map[string]*rsa.PublicKey{}
	for _, k := range doc.Keys {
		if k.Kty != "RSA" || k.Kid == "" || k.N == "" || k.E == "" {
			continue // ignore non-RSA / malformed entries rather than failing the set
		}
		nBytes, err := base64.RawURLEncoding.DecodeString(k.N)
		if err != nil {
			continue
		}
		eBytes, err := base64.RawURLEncoding.DecodeString(k.E)
		if err != nil {
			continue
		}
		e := new(big.Int).SetBytes(eBytes).Int64()
		if e <= 0 {
			continue
		}
		out[k.Kid] = &rsa.PublicKey{N: new(big.Int).SetBytes(nBytes), E: int(e)}
	}
	if len(out) == 0 {
		return nil, errors.New("jwks: no usable RSA keys")
	}
	return out, nil
}

// verifyIDToken validates raw against p and returns its claims. Signature is
// checked against the provider JWKS; algorithm is pinned to RS256 (defeats
// alg=none and HS256-confusion); issuer/expiration/audience/subject are enforced.
func (c *jwksCache) verifyIDToken(ctx context.Context, p oidcProvider, raw string, now time.Time) (*idClaims, error) {
	keyFunc := func(t *jwt.Token) (interface{}, error) {
		kid, _ := t.Header["kid"].(string)
		if kid == "" {
			return nil, errors.New("token missing kid")
		}
		return c.keyForKid(ctx, p.jwksURL, kid, now)
	}

	claims := jwt.MapClaims{}
	_, err := jwt.ParseWithClaims(raw, claims, keyFunc,
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(func() time.Time { return now }),
	)
	if err != nil {
		return nil, err
	}

	// Issuer is validated manually (a provider may accept more than one iss form);
	// the returned claims carry the CANONICAL issuer so account keying is stable.
	if iss, _ := claims["iss"].(string); !p.issuerAccepted(iss) {
		return nil, errBadIssuer
	}
	if !audienceAccepted(claims["aud"], p.audiences) {
		return nil, errBadAudience
	}

	// The subject is an OPAQUE provider identifier — validate it as-is and never
	// canonicalize (trimming would collapse distinct identities like "a" and " a "
	// and could hide length-limit overflow behind whitespace) — codex review.
	sub, _ := claims["sub"].(string)
	if sub == "" || len(sub) > maxDeviceIDLen || !isPrintableASCII(sub) {
		return nil, errBadSubject
	}

	email, _ := claims["email"].(string)
	nonce, _ := claims["nonce"].(string)
	return &idClaims{Issuer: p.issuer, Subject: sub, Email: email, Nonce: nonce}, nil
}

// audienceAccepted reports whether the token's aud (a string or []string) contains
// any of our accepted audiences.
func audienceAccepted(aud any, accepted []string) bool {
	var got []string
	switch v := aud.(type) {
	case string:
		got = []string{v}
	case []any:
		for _, a := range v {
			if s, ok := a.(string); ok {
				got = append(got, s)
			}
		}
	case []string:
		got = v
	}
	for _, g := range got {
		for _, a := range accepted {
			if a != "" && g == a {
				return true
			}
		}
	}
	return false
}

// nonceHashMatches reports whether the id_token's nonce claim equals the SHA-256
// hash (lowercase hex) of the raw nonce we issued — the binding Apple/Google use so
// a captured token can't be replayed against a different auth attempt (codex C1).
func nonceHashMatches(rawNonce, claimNonce string) bool {
	sum := sha256.Sum256([]byte(rawNonce))
	want := hex.EncodeToString(sum[:])
	return subtle.ConstantTimeCompare([]byte(want), []byte(strings.ToLower(claimNonce))) == 1
}

// issueSession mints a stateless HS256 session for accountID. ver is the account's
// current token version; requireAccount rejects a session whose ver is stale.
func issueSession(secret []byte, accountID string, ver int, now time.Time) (string, error) {
	claims := jwt.MapClaims{
		"sub": accountID,
		"ver": ver,
		"iat": now.Unix(),
		"exp": now.Add(sessionTTL).Unix(),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(secret)
}

// parseSession validates a session token's signature (HS256 only) and expiry and
// returns the account id + token version it asserts. It does NOT check that the
// account still exists / the version is current — requireAccount does that against
// the store on every request.
func parseSession(secret []byte, raw string, now time.Time) (accountID string, ver int, err error) {
	claims := jwt.MapClaims{}
	_, err = jwt.ParseWithClaims(raw, claims, func(*jwt.Token) (interface{}, error) {
		return secret, nil
	},
		jwt.WithValidMethods([]string{"HS256"}),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(func() time.Time { return now }),
	)
	if err != nil {
		return "", 0, err
	}
	accountID, _ = claims["sub"].(string)
	if accountID == "" {
		return "", 0, errBadSession
	}
	// ver must be present and a non-negative integer — a missing/fractional/negative
	// value must not silently coerce to 0 and defeat token-version revocation (codex
	// review C2). JSON numbers decode to float64.
	v, ok := claims["ver"].(float64)
	if !ok || v < 0 || v != math.Trunc(v) {
		return "", 0, errBadSession
	}
	return accountID, int(v), nil
}
