package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// anthropicRequest is the subset of the Messages API request body the seam sets.
type anthropicRequest struct {
	Model    string `json:"model"`
	Messages []struct {
		Role    string `json:"role"`
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	} `json:"messages"`
}

// fakeAnthropic serves the Messages endpoint: it records the outbound request and
// replies with the given text (as a single text content block).
func fakeAnthropic(t *testing.T, replyText string, got *anthropicRequest) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/messages" {
			t.Errorf("anthropic path = %s, want /v1/messages", r.URL.Path)
		}
		if got != nil {
			if err := json.NewDecoder(r.Body).Decode(got); err != nil {
				t.Errorf("decode anthropic body: %v", err)
			}
		}
		content := []map[string]any{}
		if replyText != "" {
			content = append(content, map[string]any{"type": "text", "text": replyText})
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":          "msg_test",
			"type":        "message",
			"role":        "assistant",
			"model":       "claude-opus-4-8",
			"content":     content,
			"stop_reason": "end_turn",
			"usage":       map[string]any{"input_tokens": 1, "output_tokens": 1},
		})
	}))
}

// anthropicTestServer builds a server whose Anthropic client targets baseURL.
func anthropicTestServer(baseURL, kagiURL string) *server {
	cfg := config{
		aiProvider:       aiProviderAnthropic,
		anthropicAPIKey:  "test-key",
		anthropicModel:   "claude-opus-4-8",
		anthropicBaseURL: baseURL,
		kagiURL:          kagiURL,
		timeout:          5 * time.Second,
		quotaStore:       "memory",
	}
	return &server{
		cfg:             cfg,
		http:            &http.Client{Timeout: 5 * time.Second},
		anthropicClient: newAnthropicClient(cfg),
		quota:           NewInMemoryQuotaStore(),
	}
}

func TestValidateAIConfig(t *testing.T) {
	cases := []struct {
		name    string
		cfg     config
		wantErr bool
	}{
		{"kagi ok", config{aiProvider: aiProviderKagi}, false},
		{"anthropic with key", config{aiProvider: aiProviderAnthropic, anthropicAPIKey: "k"}, false},
		{"anthropic without key", config{aiProvider: aiProviderAnthropic}, true},
		{"anthropic blank key", config{aiProvider: aiProviderAnthropic, anthropicAPIKey: "   "}, true},
		{"unknown provider", config{aiProvider: "openai"}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateAIConfig(tc.cfg)
			if (err != nil) != tc.wantErr {
				t.Fatalf("validateAIConfig err = %v, wantErr = %v", err, tc.wantErr)
			}
		})
	}
}

func TestCallAnthropic_ShapesRequestAndExtractsText(t *testing.T) {
	var got anthropicRequest
	api := fakeAnthropic(t, "옛날 옛적에 하준이가 살았어요.", &got)
	defer api.Close()

	srv := anthropicTestServer(api.URL, "")
	text, err := srv.callAnthropic(context.Background(), "PROMPT-BODY")
	if err != nil {
		t.Fatalf("callAnthropic: %v", err)
	}
	if text != "옛날 옛적에 하준이가 살았어요." {
		t.Fatalf("text = %q", text)
	}
	if got.Model != "claude-opus-4-8" {
		t.Errorf("model = %q, want claude-opus-4-8", got.Model)
	}
	if len(got.Messages) != 1 || got.Messages[0].Role != "user" {
		t.Fatalf("messages = %+v", got.Messages)
	}
	if len(got.Messages[0].Content) != 1 || got.Messages[0].Content[0].Text != "PROMPT-BODY" {
		t.Fatalf("prompt not carried in user message: %+v", got.Messages[0].Content)
	}
}

func TestCallAnthropic_EmptyContentIsError(t *testing.T) {
	api := fakeAnthropic(t, "", nil) // no text blocks → refusal-shaped empty content
	defer api.Close()

	srv := anthropicTestServer(api.URL, "")
	if _, err := srv.callAnthropic(context.Background(), "PROMPT"); err == nil {
		t.Fatal("expected an error on empty content")
	}
}

// TestCallAnthropic_RefusalWithTextIsError proves a refusal fails safe even when it
// carries prose — that text must never reach a child as a story (codex review C1).
func TestCallAnthropic_RefusalWithTextIsError(t *testing.T) {
	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id": "msg_x", "type": "message", "role": "assistant", "model": "claude-opus-4-8",
			"content":     []map[string]any{{"type": "text", "text": "I can't help with that."}},
			"stop_reason": "refusal",
			"usage":       map[string]any{"input_tokens": 1, "output_tokens": 1},
		})
	}))
	defer api.Close()

	srv := anthropicTestServer(api.URL, "")
	if _, err := srv.callAnthropic(context.Background(), "PROMPT"); err == nil {
		t.Fatal("expected an error on a refusal, even with text present")
	}
}

// TestCallAI_DispatchAnthropic asserts the anthropic path is taken AND the kagi
// upstream is never contacted when the provider is anthropic (codex plan review I2).
func TestCallAI_DispatchAnthropic(t *testing.T) {
	api := fakeAnthropic(t, "story text", nil)
	defer api.Close()
	kagi := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Error("kagi must not be contacted when provider=anthropic")
	}))
	defer kagi.Close()

	srv := anthropicTestServer(api.URL, kagi.URL)
	text, err := srv.callAI(context.Background(), "PROMPT")
	if err != nil {
		t.Fatalf("callAI: %v", err)
	}
	if text != "story text" {
		t.Fatalf("text = %q", text)
	}
}

// TestCallAI_DispatchKagi asserts the default (kagi) path is taken AND the anthropic
// client is never invoked when the provider is kagi.
func TestCallAI_DispatchKagi(t *testing.T) {
	kagi := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"md": "kagi story"})
	}))
	defer kagi.Close()
	// A non-nil anthropic client pointed at a server that fails the test if hit.
	trap := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Error("anthropic must not be contacted when provider=kagi")
	}))
	defer trap.Close()

	cfg := config{aiProvider: aiProviderKagi, kagiURL: kagi.URL, timeout: 5 * time.Second, anthropicBaseURL: trap.URL, anthropicAPIKey: "k", anthropicModel: "claude-opus-4-8"}
	// Force the anthropic branch construction so we prove dispatch, not a nil client.
	anthCfg := cfg
	anthCfg.aiProvider = aiProviderAnthropic
	srv := &server{cfg: cfg, http: &http.Client{Timeout: 5 * time.Second}, anthropicClient: newAnthropicClient(anthCfg), quota: NewInMemoryQuotaStore()}

	text, err := srv.callAI(context.Background(), "PROMPT")
	if err != nil {
		t.Fatalf("callAI: %v", err)
	}
	if !strings.Contains(text, "kagi story") {
		t.Fatalf("text = %q", text)
	}
}
