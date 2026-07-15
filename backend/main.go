// Playzy backend — the AI gateway between the app and the AI provider (ADR
// 0001). It owns the prompt and the provider; the app only speaks the stable
// Playzy contract. This implementation is the thinnest viable adapter: it
// proxies to a local `kagi serve` (POST /chat) and shapes the result into a
// Story. Swapping kagi for another provider is a change confined to callAI.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

type config struct {
	addr    string
	kagiURL string
	timeout time.Duration
	// adminToken guards privileged endpoints (credit grants). Empty → those
	// endpoints are disabled entirely. In production the verified-purchase
	// webhook presents this token; it is never known to app clients.
	adminToken string
	// kagiModel pins the base model so generations are deterministic across
	// host config changes (codex plan review C2). Ignored when kagiProfileID is
	// set (a profile carries its own model).
	kagiModel string
	// kagiProfileID optionally routes through a named Kagi custom assistant
	// (which pins that assistant's own base model). Personalization is disabled
	// explicitly on every call (see callAI), independent of the profile. Empty →
	// send the base model. Account-specific, so it has no committed default; set
	// KAGI_PROFILE_ID to enable.
	kagiProfileID string
	// quotaStore selects the authoritative quota backend: "memory" (dev) or
	// "sqlite" (durable). REQUIRED and fail-closed — there is no default, so a
	// prod deploy that omits it can't silently boot on the restart-volatile store.
	quotaStore string
	// dbPath is the SQLite file; required when quotaStore is "sqlite".
	dbPath string
	// revenueCatWebhookAuth is the shared secret RevenueCat is configured to send in
	// the Authorization header of every webhook. Empty → the webhook endpoint is
	// disabled (404), mirroring adminToken's fail-closed posture.
	revenueCatWebhookAuth string
	// revenueCatAppID, when set, restricts accepted webhook events to this RevenueCat
	// app id — defense in depth so a foreign project's event can't grant credits.
	revenueCatAppID string
	// revenueCatAllowSandbox accepts SANDBOX-environment purchase events. Dev/testing
	// only; production leaves it false so a sandbox purchase never mints real credits.
	revenueCatAllowSandbox bool
	// sessionSecret signs app session JWTs (HS256). Empty → the auth endpoints are
	// disabled (404); when set it must be ≥256 bits (validated at startup).
	sessionSecret string
	// appleClientID is the Sign in with Apple audience (Services ID / bundle id) the
	// id_token must carry. Empty → /v1/auth/apple is disabled (404).
	appleClientID string
	// googleClientID / kakaoClientID are the OIDC audiences for those providers.
	// Empty → that provider's /v1/auth/{google,kakao} endpoint is disabled (404).
	googleClientID string
	kakaoClientID  string
}

func loadConfig() config {
	return config{
		addr:          envOr("PLAYZY_ADDR", ":8080"),
		kagiURL:       envOr("KAGI_SERVE_URL", "http://127.0.0.1:8921"),
		timeout:       120 * time.Second,
		adminToken:    os.Getenv("PLAYZY_ADMIN_TOKEN"),
		kagiModel:     envOr("KAGI_MODEL", "claude-5-sonnet"),
		kagiProfileID: os.Getenv("KAGI_PROFILE_ID"),
		quotaStore:    os.Getenv("PLAYZY_QUOTA_STORE"),
		dbPath:        os.Getenv("PLAYZY_DB_PATH"),

		revenueCatWebhookAuth:  os.Getenv("REVENUECAT_WEBHOOK_AUTH"),
		revenueCatAppID:        os.Getenv("REVENUECAT_APP_ID"),
		revenueCatAllowSandbox: os.Getenv("REVENUECAT_ALLOW_SANDBOX") == "1",

		sessionSecret:  os.Getenv("PLAYZY_SESSION_SECRET"),
		appleClientID:  os.Getenv("APPLE_CLIENT_ID"),
		googleClientID: os.Getenv("GOOGLE_CLIENT_ID"),
		kakaoClientID:  os.Getenv("KAKAO_CLIENT_ID"),
	}
}

// dataStore is the full persistence surface — quota, accounts, and login nonces.
// Both the in-memory and SQLite backends implement all three, so one instance
// serves everything.
type dataStore interface {
	QuotaStore
	AccountStore
	NonceStore
	DocStore
}

// newQuotaStore builds the authoritative store from config, fail-closed: an
// unset/unknown selector is a fatal misconfiguration (never a silent fallback to
// a data-losing store). Returns the store and a close func.
func newQuotaStore(cfg config) (dataStore, func() error, error) {
	switch cfg.quotaStore {
	case "memory":
		return NewInMemoryQuotaStore(), func() error { return nil }, nil
	case "sqlite":
		if cfg.dbPath == "" {
			return nil, nil, errors.New("PLAYZY_QUOTA_STORE=sqlite requires PLAYZY_DB_PATH")
		}
		st, err := OpenSQLiteQuotaStore(cfg.dbPath)
		if err != nil {
			return nil, nil, err
		}
		return st, st.Close, nil
	default:
		return nil, nil, fmt.Errorf("PLAYZY_QUOTA_STORE must be 'memory' or 'sqlite' (got %q)", cfg.quotaStore)
	}
}

// newMux registers all routes. Extracted so tests can exercise the real routing
// (method + path) rather than calling handlers directly.
func newMux(srv *server) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/stories", srv.handleStories)
	mux.HandleFunc("GET /v1/catalog/situations", srv.handleCatalog)
	mux.HandleFunc("GET /v1/quota", srv.handleQuota)
	mux.HandleFunc("POST /v1/credits", srv.handleGrantCredits)
	mux.HandleFunc("POST /v1/webhooks/revenuecat", srv.handleRevenueCatWebhook)
	mux.HandleFunc("POST /v1/auth/nonce", srv.handleAuthNonce)
	mux.HandleFunc("POST /v1/auth/apple", srv.handleAppleAuth)
	mux.HandleFunc("POST /v1/auth/google", srv.handleGoogleAuth)
	mux.HandleFunc("POST /v1/auth/kakao", srv.handleKakaoAuth)
	mux.HandleFunc("GET /v1/me", srv.handleMe)
	mux.HandleFunc("DELETE /v1/me", srv.handleDeleteMe)
	mux.HandleFunc("GET /v1/profile", srv.handleGetProfile)
	mux.HandleFunc("PUT /v1/profile", srv.handlePutProfile)
	mux.HandleFunc("GET /v1/roster", srv.handleGetRoster)
	mux.HandleFunc("PUT /v1/roster", srv.handlePutRoster)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})
	return mux
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	cfg := loadConfig()
	store, closeStore, err := newQuotaStore(cfg)
	if err != nil {
		log.Fatalf("quota store: %v", err)
	}

	// Auth is enabled only with a configured session secret, which must be strong
	// enough that HS256 sessions can't be forged (fail startup on a weak secret).
	if cfg.sessionSecret != "" {
		if err := validateSessionSecret(cfg.sessionSecret); err != nil {
			log.Fatalf("auth config: %v", err)
		}
	}

	srv := &server{
		cfg:           cfg,
		http:          &http.Client{Timeout: cfg.timeout},
		quota:         store,
		accounts:      store,
		nonces:        store,
		docs:          store,
		sessionSecret: []byte(cfg.sessionSecret),
		jwks:          newJWKSCache(&http.Client{Timeout: 10 * time.Second}),
		apple:         appleProvider(cfg.appleClientID),
		google:        googleProvider(cfg.googleClientID),
		kakao:         kakaoProvider(cfg.kakaoClientID),
		now:           time.Now,
	}

	httpSrv := &http.Server{Addr: cfg.addr, Handler: newMux(srv)}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Printf("playzy backend on %s → kagi %s (quota store: %s)", cfg.addr, cfg.kagiURL, cfg.quotaStore)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen: %v", err)
		}
	}()

	<-ctx.Done()
	stop() // restore default signal handling so a second signal force-quits
	log.Print("shutting down…")

	// Fresh, bounded context (the signal ctx is already cancelled) so shutdown
	// can actually drain in-flight requests before the DB is closed.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown: %v", err)
	}
	if err := closeStore(); err != nil {
		log.Printf("close store: %v", err)
	}
}

type server struct {
	cfg   config
	http  *http.Client
	quota QuotaStore

	// Auth (WU3). Set when PLAYZY_SESSION_SECRET is configured; the auth handlers
	// are disabled (404) otherwise.
	accounts      AccountStore
	nonces        NonceStore
	docs          DocStore
	sessionSecret []byte
	jwks          *jwksCache
	apple         oidcProvider
	google        oidcProvider
	kakao         oidcProvider
	// now is the clock for session/nonce timestamps; injectable for tests.
	now clock
}

// deviceID identifies the caller for quota (ADR 0002). The app sends a stable,
// locally-generated id; a real launch pairs this with account auth.
const deviceHeader = "X-Device-Id"

// maxDeviceIDLen bounds the client-supplied id so it can't be used to write
// unbounded rows / exhaust storage in the durable store. The app's id is a
// 32-char hex string, so this is generous.
const maxDeviceIDLen = 128

// requestDeviceID validates and returns the caller's device id, or writes a 400
// and returns ok=false. Bounding length + charset keeps a crafted header from
// growing the store without limit.
func requestDeviceID(w http.ResponseWriter, r *http.Request) (string, bool) {
	id := strings.TrimSpace(r.Header.Get(deviceHeader))
	if id == "" {
		httpError(w, http.StatusBadRequest, deviceHeader+" header is required")
		return "", false
	}
	if len(id) > maxDeviceIDLen || !isPrintableASCII(id) {
		httpError(w, http.StatusBadRequest, deviceHeader+" is malformed")
		return "", false
	}
	return id, true
}

func isPrintableASCII(s string) bool {
	for _, r := range s {
		if r < 0x20 || r > 0x7e {
			return false
		}
	}
	return true
}

func (s *server) handleStories(w http.ResponseWriter, r *http.Request) {
	// Bound the request body so a crafted payload (e.g. a huge character list)
	// can't exhaust memory before validation (planning/40, C1).
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MiB
	var req StoryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	subject, ok := s.resolveSubject(w, r)
	if !ok {
		return
	}
	req.ChildName = strings.TrimSpace(req.ChildName)
	req.SituationIDs = nonEmpty(req.SituationIDs)
	// Normalize the free-text seed BEFORE validating so a whitespace/control-only
	// topic can't satisfy the check yet contribute no material (C3). The prompt
	// builder re-sanitizes, so the stored value stays the normalized one.
	req.Topic = sanitizeTopic(req.Topic)
	if req.ChildName == "" || (len(req.SituationIDs) == 0 && req.Topic == "") {
		httpError(w, http.StatusBadRequest, "childName and either a topic or at least one situationId are required")
		return
	}

	// Authoritative quota (ADR 0002): place a pending hold before generating —
	// commit only once the story is delivered, release on failure. A failed or
	// abandoned generation is never charged, and it can't be bypassed
	// client-side. Persistence + crash-safety live in the store (quota_sqlite.go).
	resID, err := s.quota.Reserve(subject)
	if errors.Is(err, errQuotaExceeded) {
		httpError(w, http.StatusPaymentRequired, "free stories used up — purchase credits to continue")
		return
	}
	if err != nil {
		// Infrastructure failure (e.g. the production store) — not "out of quota".
		log.Printf("quota reserve: %v", err)
		httpError(w, http.StatusInternalServerError, "quota check failed")
		return
	}

	// In profile mode the Kagi assistant's instructions ARE the system prompt
	// (created from prompts/story_author_system.md), so send only the materials.
	// Otherwise send the self-contained prompt (system + materials) so a base
	// model still works. Either way the .md is the single versioned source.
	prompt := buildStoryPrompt(req)
	if s.cfg.kagiProfileID != "" {
		prompt = buildStoryMaterials(req)
	}
	text, err := s.callAI(r.Context(), prompt)
	if err != nil {
		s.quota.Release(resID)
		log.Printf("callAI: %v", err)
		httpError(w, http.StatusBadGateway, "story generation failed")
		return
	}

	story := parseStory(text, req)
	story.CreatedAt = time.Now().UTC().Format(time.RFC3339)
	if err := writeJSON(w, http.StatusOK, story); err != nil {
		// The client vanished before receiving the story — release the hold
		// rather than charge for a story that wasn't delivered.
		s.quota.Release(resID)
		log.Printf("deliver story: %v", err)
		return
	}

	// Charge only after writing the story: an abandoned/failed generation is never
	// charged, and a *detected* delivery failure (above) releases the hold. A
	// residual window remains — a successful Encode doesn't prove client receipt
	// (net/http may buffer; the connection can still drop), so a rare
	// buffered-but-undelivered story can be charged. It's bounded to a single unit
	// and is irreducible here: "charged iff delivered" needs request idempotency +
	// a client-confirmed delivery step, which arrives with server-side story
	// persistence in a later WU.
	if err := s.quota.Commit(resID); err != nil {
		log.Printf("quota commit %s: %v", resID, err)
	}
}

// GET /v1/quota — the app reads authoritative remaining allowance.
func (s *server) handleQuota(w http.ResponseWriter, r *http.Request) {
	subject, ok := s.resolveSubject(w, r)
	if !ok {
		return
	}
	st, err := s.quota.State(subject)
	if err != nil {
		log.Printf("quota state: %v", err)
		httpError(w, http.StatusInternalServerError, "quota check failed")
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// POST /v1/credits — grant purchased credits. Privileged: requires the admin
// token (the verified StoreKit/RevenueCat purchase webhook presents it). Never
// callable by app clients. Disabled entirely when no admin token is configured.
func (s *server) handleGrantCredits(w http.ResponseWriter, r *http.Request) {
	if s.cfg.adminToken == "" {
		httpError(w, http.StatusNotFound, "not found")
		return
	}
	if r.Header.Get("X-Admin-Token") != s.cfg.adminToken {
		httpError(w, http.StatusForbidden, "forbidden")
		return
	}
	deviceID, ok := requestDeviceID(w, r)
	if !ok {
		return
	}
	var body struct {
		Amount         int    `json:"amount"`
		IdempotencyKey string `json:"idempotencyKey"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Amount <= 0 || body.Amount > maxGrant {
		httpError(w, http.StatusBadRequest, fmt.Sprintf("amount must be between 1 and %d", maxGrant))
		return
	}
	// The real verified-purchase webhook always supplies the purchase id as the
	// idempotency key, so a redelivered webhook grants once. Requiring it at this
	// trust boundary prevents a retried keyless grant from re-crediting. Keyless
	// is a convenience allowed ONLY for the in-memory (dev) store — production
	// runs sqlite and must supply the key.
	key := strings.TrimSpace(body.IdempotencyKey)
	if key == "" {
		if s.cfg.quotaStore != "memory" {
			httpError(w, http.StatusBadRequest, "idempotencyKey is required")
			return
		}
		key = newReservationID()
	}
	if err := s.quota.AddCredits(deviceID, body.Amount, key); err != nil {
		if errors.Is(err, errGrantConflict) {
			httpError(w, http.StatusConflict, "idempotency key reused with a different grant")
			return
		}
		log.Printf("quota add credits: %v", err)
		httpError(w, http.StatusInternalServerError, "credit grant failed")
		return
	}
	st, err := s.quota.State(deviceID)
	if err != nil {
		log.Printf("quota state: %v", err)
		httpError(w, http.StatusInternalServerError, "quota check failed")
		return
	}
	writeJSON(w, http.StatusOK, st)
}

func (s *server) handleCatalog(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, situationCatalogSDUI())
}

// callAI is the provider seam. Today it calls `kagi serve`; swap the body to
// target OpenAI/Anthropic/etc. without touching the rest of the backend.
func (s *server) callAI(ctx context.Context, prompt string) (string, error) {
	// Always disable internet + personalization: a story needs no web search and
	// must not leak the account's personal context, and it keeps output
	// deterministic. Pin the assistant explicitly rather than relying on mutable
	// kagi-host defaults (codex plan review C2). A profile pins that assistant's
	// model; otherwise pin the base model directly.
	payload := map[string]any{
		"prompt":          prompt,
		"internet_access": false,
		"personalization": false,
	}
	if s.cfg.kagiProfileID != "" {
		payload["profile_id"] = s.cfg.kagiProfileID
	} else {
		payload["model"] = s.cfg.kagiModel
	}
	body, _ := json.Marshal(payload)
	url := s.cfg.kagiURL + "/chat"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	httpReq.Header.Set("content-type", "application/json")

	res, err := s.http.Do(httpReq)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	raw, err := io.ReadAll(res.Body)
	if err != nil {
		return "", fmt.Errorf("read kagi response: %w", err)
	}
	if res.StatusCode != http.StatusOK {
		return "", fmt.Errorf("kagi %d: %s", res.StatusCode, string(raw))
	}
	return extractKagiText(raw)
}

// extractKagiText pulls the assistant markdown out of a kagi /chat response.
// kagi's JSON exposes the text under `md`; we also try common fallbacks so a
// minor upstream shape change doesn't break us immediately.
func extractKagiText(raw []byte) (string, error) {
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		return "", fmt.Errorf("kagi response not JSON: %w", err)
	}
	for _, key := range []string{"md", "content", "text", "message"} {
		if v, ok := m[key].(string); ok && v != "" {
			return v, nil
		}
	}
	return "", fmt.Errorf("no text field in kagi response")
}

// writeJSON writes v as the response body and returns the encode/write error so
// a caller at a charge boundary can tell whether delivery actually succeeded.
func writeJSON(w http.ResponseWriter, status int, v any) error {
	w.Header().Set("content-type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	return json.NewEncoder(w).Encode(v)
}

func httpError(w http.ResponseWriter, status int, msg string) {
	_ = writeJSON(w, status, map[string]string{"error": msg})
}

// nonEmpty drops blank/whitespace-only entries from a string slice.
func nonEmpty(in []string) []string {
	out := make([]string, 0, len(in))
	for _, s := range in {
		if strings.TrimSpace(s) != "" {
			out = append(out, strings.TrimSpace(s))
		}
	}
	return out
}
