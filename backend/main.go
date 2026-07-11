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
	"strings"
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
	// (which pins that assistant's own base model). NOTE: the current `kagi
	// serve` path sends personalization=true per message, so a profile's
	// no-personalize setting is NOT honored here — disabling it would need a
	// kagi change. Empty → send the base model. Account-specific, so it has no
	// committed default; set KAGI_PROFILE_ID to enable.
	kagiProfileID string
}

func loadConfig() config {
	return config{
		addr:          envOr("PLAYZY_ADDR", ":8080"),
		kagiURL:       envOr("KAGI_SERVE_URL", "http://127.0.0.1:8921"),
		timeout:       120 * time.Second,
		adminToken:    os.Getenv("PLAYZY_ADMIN_TOKEN"),
		kagiModel:     envOr("KAGI_MODEL", "claude-5-sonnet"),
		kagiProfileID: os.Getenv("KAGI_PROFILE_ID"),
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	cfg := loadConfig()
	srv := &server{
		cfg:   cfg,
		http:  &http.Client{Timeout: cfg.timeout},
		quota: NewInMemoryQuotaStore(),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/stories", srv.handleStories)
	mux.HandleFunc("GET /v1/catalog/situations", srv.handleCatalog)
	mux.HandleFunc("GET /v1/quota", srv.handleQuota)
	mux.HandleFunc("POST /v1/credits", srv.handleGrantCredits)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})

	log.Printf("playzy backend on %s → kagi %s", cfg.addr, cfg.kagiURL)
	if err := http.ListenAndServe(cfg.addr, mux); err != nil {
		log.Fatal(err)
	}
}

type server struct {
	cfg   config
	http  *http.Client
	quota QuotaStore
}

// deviceID identifies the caller for quota (ADR 0002). The app sends a stable,
// locally-generated id; a real launch pairs this with account auth.
const deviceHeader = "X-Device-Id"

func (s *server) handleStories(w http.ResponseWriter, r *http.Request) {
	// Bound the request body so a crafted payload (e.g. a huge character list)
	// can't exhaust memory before validation (planning/40, C1).
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MiB
	var req StoryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	deviceID := strings.TrimSpace(r.Header.Get(deviceHeader))
	if deviceID == "" {
		httpError(w, http.StatusBadRequest, deviceHeader+" header is required")
		return
	}
	req.ChildName = strings.TrimSpace(req.ChildName)
	req.SituationIDs = nonEmpty(req.SituationIDs)
	if req.ChildName == "" || len(req.SituationIDs) == 0 {
		httpError(w, http.StatusBadRequest, "childName and at least one situationId are required")
		return
	}

	// Authoritative quota (ADR 0002): reserve before generating, refund on
	// failure — a failed generation is never charged, and it can't be bypassed
	// client-side.
	c, err := s.quota.Reserve(deviceID)
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

	prompt := buildStoryPrompt(req)
	text, err := s.callAI(r.Context(), prompt)
	if err != nil {
		s.quota.Refund(deviceID, c)
		log.Printf("callAI: %v", err)
		httpError(w, http.StatusBadGateway, "story generation failed")
		return
	}

	story := parseStory(text, req)
	story.CreatedAt = time.Now().UTC().Format(time.RFC3339)
	writeJSON(w, http.StatusOK, story)
}

// GET /v1/quota — the app reads authoritative remaining allowance.
func (s *server) handleQuota(w http.ResponseWriter, r *http.Request) {
	deviceID := strings.TrimSpace(r.Header.Get(deviceHeader))
	if deviceID == "" {
		httpError(w, http.StatusBadRequest, deviceHeader+" header is required")
		return
	}
	writeJSON(w, http.StatusOK, s.quota.State(deviceID))
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
	deviceID := strings.TrimSpace(r.Header.Get(deviceHeader))
	if deviceID == "" {
		httpError(w, http.StatusBadRequest, deviceHeader+" header is required")
		return
	}
	var body struct {
		Amount int `json:"amount"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Amount <= 0 {
		httpError(w, http.StatusBadRequest, "positive amount required")
		return
	}
	s.quota.AddCredits(deviceID, body.Amount)
	writeJSON(w, http.StatusOK, s.quota.State(deviceID))
}

func (s *server) handleCatalog(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, situationCatalogSDUI())
}

// callAI is the provider seam. Today it calls `kagi serve`; swap the body to
// target OpenAI/Anthropic/etc. without touching the rest of the backend.
func (s *server) callAI(ctx context.Context, prompt string) (string, error) {
	// Always disable internet (a story needs no web search; keeps output
	// deterministic) and pin the assistant explicitly rather than relying on
	// mutable kagi-host defaults (codex plan review C2). A profile pins that
	// assistant's model; otherwise pin the base model directly. (Personalization
	// is not controllable via kagi serve yet — see config.kagiProfileID.)
	payload := map[string]any{"prompt": prompt, "internet_access": false}
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

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("content-type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func httpError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
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
