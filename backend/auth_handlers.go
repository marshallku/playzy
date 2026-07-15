package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"
)

// Auth HTTP surface (WU3): server-issued single-use nonce → provider login →
// session, plus the session-guarded account endpoints. All disabled (404) unless a
// session secret is configured.

func (s *server) authEnabled() bool { return len(s.sessionSecret) > 0 }

// resolveSubject returns the quota/entitlement subject for a request: the account id
// when the caller presents a valid Bearer session, else the anonymous X-Device-Id.
// A device id may not use the reserved account prefix, so an anonymous caller can't
// present an account-shaped subject to reach an account's quota. Invalid Bearer → 401
// (a broken session must not silently fall back to device scope).
func (s *server) resolveSubject(w http.ResponseWriter, r *http.Request) (string, bool) {
	// Any Authorization header at all is an auth ATTEMPT: it must be a valid Bearer
	// session (requireAccount 401s otherwise) — a malformed one must never silently
	// fall back to device scope. Only a wholly absent header is anonymous.
	if s.authEnabled() && r.Header.Get("Authorization") != "" {
		acct, ok := s.requireAccount(w, r)
		if !ok {
			return "", false
		}
		return acct.ID, true
	}
	deviceID, ok := requestDeviceID(w, r)
	if !ok {
		return "", false
	}
	if strings.HasPrefix(deviceID, accountIDPrefix) {
		httpError(w, http.StatusBadRequest, deviceHeader+" must not use the reserved account prefix")
		return "", false
	}
	return deviceID, true
}

// handleAuthNonce issues a single-use, short-lived login nonce. The client hashes
// it (sha256) into the provider authorization request and returns the raw value to
// the login endpoint, binding the resulting id_token to this attempt (anti-replay).
func (s *server) handleAuthNonce(w http.ResponseWriter, _ *http.Request) {
	if !s.authEnabled() {
		httpError(w, http.StatusNotFound, "not found")
		return
	}
	nonce, err := s.nonces.IssueNonce(s.now())
	if err != nil {
		log.Printf("issue nonce: %v", err)
		httpError(w, http.StatusInternalServerError, "could not issue nonce")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"nonce": nonce})
}

// oidcAuth is the shared provider login endpoint: it verifies a provider id_token
// bound to a server nonce, upserts the account, and returns a session. Disabled (404)
// unless auth is configured AND this provider has a client id (audience) set.
func (s *server) oidcAuth(w http.ResponseWriter, r *http.Request, p oidcProvider, clientID string) {
	if !s.authEnabled() || clientID == "" {
		httpError(w, http.StatusNotFound, "not found")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var body struct {
		IDToken string `json:"idToken"`
		Nonce   string `json:"nonce"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.IDToken == "" || body.Nonce == "" {
		httpError(w, http.StatusBadRequest, "idToken and nonce are required")
		return
	}
	s.completeOIDCLogin(w, r, p, body.IDToken, body.Nonce)
}

// Per-provider endpoints. Each verifies that provider's id_token against its own
// issuer/JWKS/audience; all share the account model and session issuance.
func (s *server) handleAppleAuth(w http.ResponseWriter, r *http.Request) {
	s.oidcAuth(w, r, s.apple, s.cfg.appleClientID)
}

func (s *server) handleGoogleAuth(w http.ResponseWriter, r *http.Request) {
	s.oidcAuth(w, r, s.google, s.cfg.googleClientID)
}

func (s *server) handleKakaoAuth(w http.ResponseWriter, r *http.Request) {
	s.oidcAuth(w, r, s.kakao, s.cfg.kakaoClientID)
}

// completeOIDCLogin is the shared provider login path (Apple now; Google/Kakao join
// in WU3b): verify the id_token, enforce the single-use nonce binding, upsert the
// account, and return a session.
func (s *server) completeOIDCLogin(w http.ResponseWriter, r *http.Request, p oidcProvider, idToken, rawNonce string) {
	now := s.now()
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	// Consume the nonce FIRST, so it is a true one-shot challenge: every attempt —
	// even one with a malformed or mismatched token — burns it, leaving no window to
	// retry token verification against the same server-issued nonce (codex review).
	ok, err := s.nonces.ConsumeNonce(rawNonce, now)
	if err != nil {
		log.Printf("consume nonce: %v", err)
		httpError(w, http.StatusInternalServerError, "login failed")
		return
	}
	if !ok {
		httpError(w, http.StatusUnauthorized, "nonce expired or already used")
		return
	}

	claims, err := s.jwks.verifyIDToken(ctx, p, idToken, now)
	if err != nil {
		httpError(w, http.StatusUnauthorized, "invalid id token")
		return
	}
	// The token's nonce claim must be sha256(the raw nonce we issued) — this binds
	// the (now-consumed) challenge to this specific token.
	if !nonceHashMatches(rawNonce, claims.Nonce) {
		httpError(w, http.StatusUnauthorized, "nonce mismatch")
		return
	}

	accountID, created, err := s.accounts.UpsertIdentity(claims.Issuer, claims.Subject, claims.Email, now)
	if err != nil {
		log.Printf("upsert identity: %v", err)
		httpError(w, http.StatusInternalServerError, "login failed")
		return
	}
	acct, err := s.accounts.GetAccount(accountID)
	if err != nil {
		log.Printf("get account: %v", err)
		httpError(w, http.StatusInternalServerError, "login failed")
		return
	}
	token, err := issueSession(s.sessionSecret, accountID, acct.TokenVersion, now)
	if err != nil {
		log.Printf("issue session: %v", err)
		httpError(w, http.StatusInternalServerError, "login failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"token":   token,
		"account": map[string]string{"id": accountID},
		"isNew":   created,
	})
}

// requireAccount authenticates the caller from the Bearer session and returns the
// current account. It checks the store on every request, so a deleted account or a
// bumped token version invalidates the session immediately.
func (s *server) requireAccount(w http.ResponseWriter, r *http.Request) (account, bool) {
	if !s.authEnabled() {
		httpError(w, http.StatusNotFound, "not found")
		return account{}, false
	}
	const prefix = "Bearer "
	authz := r.Header.Get("Authorization")
	if !strings.HasPrefix(authz, prefix) {
		httpError(w, http.StatusUnauthorized, "missing bearer token")
		return account{}, false
	}
	accountID, ver, err := parseSession(s.sessionSecret, strings.TrimPrefix(authz, prefix), s.now())
	if err != nil {
		httpError(w, http.StatusUnauthorized, "invalid session")
		return account{}, false
	}
	acct, err := s.accounts.GetAccount(accountID)
	if err != nil {
		httpError(w, http.StatusUnauthorized, "invalid session") // deleted/unknown account
		return account{}, false
	}
	if ver != acct.TokenVersion {
		httpError(w, http.StatusUnauthorized, "session revoked")
		return account{}, false
	}
	return acct, true
}

func (s *server) handleMe(w http.ResponseWriter, r *http.Request) {
	acct, ok := s.requireAccount(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"id":        acct.ID,
		"createdAt": acct.CreatedAt.UTC().Format(time.RFC3339),
	})
}

func (s *server) handleDeleteMe(w http.ResponseWriter, r *http.Request) {
	acct, ok := s.requireAccount(w, r)
	if !ok {
		return
	}
	if err := s.accounts.DeleteAccount(acct.ID); err != nil && !errors.Is(err, errAccountNotFound) {
		log.Printf("delete account: %v", err)
		httpError(w, http.StatusInternalServerError, "could not delete account")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
