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
}

func loadConfig() config {
	return config{
		addr:    envOr("PLAYZY_ADDR", ":8080"),
		kagiURL: envOr("KAGI_SERVE_URL", "http://127.0.0.1:8921"),
		timeout: 120 * time.Second,
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
	srv := &server{cfg: cfg, http: &http.Client{Timeout: cfg.timeout}}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/stories", srv.handleStories)
	mux.HandleFunc("GET /v1/catalog/situations", srv.handleCatalog)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})

	log.Printf("playzy backend on %s → kagi %s", cfg.addr, cfg.kagiURL)
	if err := http.ListenAndServe(cfg.addr, mux); err != nil {
		log.Fatal(err)
	}
}

type server struct {
	cfg  config
	http *http.Client
}

func (s *server) handleStories(w http.ResponseWriter, r *http.Request) {
	var req StoryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	req.ChildName = strings.TrimSpace(req.ChildName)
	req.SituationIDs = nonEmpty(req.SituationIDs)
	if req.ChildName == "" || len(req.SituationIDs) == 0 {
		httpError(w, http.StatusBadRequest, "childName and at least one situationId are required")
		return
	}

	prompt := buildStoryPrompt(req)
	text, err := s.callAI(r.Context(), prompt)
	if err != nil {
		log.Printf("callAI: %v", err)
		httpError(w, http.StatusBadGateway, "story generation failed")
		return
	}

	story := parseStory(text, req)
	story.CreatedAt = time.Now().UTC().Format(time.RFC3339)
	writeJSON(w, http.StatusOK, story)
}

func (s *server) handleCatalog(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, situationCatalogSDUI())
}

// callAI is the provider seam. Today it calls `kagi serve`; swap the body to
// target OpenAI/Anthropic/etc. without touching the rest of the backend.
func (s *server) callAI(ctx context.Context, prompt string) (string, error) {
	body, _ := json.Marshal(map[string]any{"prompt": prompt})
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
