package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func newTestServer(kagiURL string) *server {
	return &server{
		cfg:   config{kagiURL: kagiURL, timeout: 5 * time.Second, adminToken: "test-admin"},
		http:  &http.Client{Timeout: 5 * time.Second},
		quota: NewInMemoryQuotaStore(),
	}
}

// storyRequest builds a POST /v1/stories request with the required device header.
func storyRequest(body, deviceID string) *http.Request {
	req := httptest.NewRequest(http.MethodPost, "/v1/stories", strings.NewReader(body))
	if deviceID != "" {
		req.Header.Set(deviceHeader, deviceID)
	}
	return req
}

func TestHandleStories_HappyPath(t *testing.T) {
	// Fake kagi returns the story JSON under `md`.
	kagi := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/chat" {
			t.Errorf("kagi path = %s", r.URL.Path)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"md": `{"title":"하준의 밤","pages":[{"text":"옛날 옛적에"}]}`,
		})
	}))
	defer kagi.Close()

	srv := newTestServer(kagi.URL)
	body := `{"childName":"하준","ageBand":"toddler","situationIds":["bedtime"]}`
	req := storyRequest(body, "dev1")
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var story Story
	if err := json.Unmarshal(rec.Body.Bytes(), &story); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if story.Title != "하준의 밤" || len(story.Pages) != 1 {
		t.Fatalf("story = %+v", story)
	}
	if story.CreatedAt == "" {
		t.Error("createdAt should be set")
	}
}

// captureKagi returns a fake kagi that records the decoded /chat request body
// and replies with a minimal valid story.
func captureKagi(t *testing.T, got *map[string]any) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(got); err != nil {
			t.Errorf("decode kagi body: %v", err)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"md": `{"title":"t","pages":[{"text":"p"}]}`,
		})
	}))
}

func TestCallAI_PinsModelAndDisablesInternet(t *testing.T) {
	// Default (no profile): the request must pin the base model and disable
	// internet rather than depend on mutable kagi-host defaults (C2).
	var got map[string]any
	kagi := captureKagi(t, &got)
	defer kagi.Close()
	srv := newTestServer(kagi.URL)
	srv.cfg.kagiModel = "claude-5-sonnet"
	rec := httptest.NewRecorder()
	srv.handleStories(rec, storyRequest(`{"childName":"하준","ageBand":"toddler","situationIds":["bedtime"]}`, "dev1"))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	if got["internet_access"] != false {
		t.Errorf("internet_access = %v, want false", got["internet_access"])
	}
	if got["model"] != "claude-5-sonnet" {
		t.Errorf("model = %v, want claude-5-sonnet", got["model"])
	}
	if got["personalization"] != false {
		t.Errorf("personalization = %v, want false", got["personalization"])
	}
	if _, ok := got["profile_id"]; ok {
		t.Errorf("profile_id must be absent when unconfigured")
	}
}

func TestCallAI_UsesProfileWhenConfigured(t *testing.T) {
	// With a profile: route through it (pins the assistant's own model); model is
	// then omitted so the profile's model applies. Internet stays disabled.
	var got map[string]any
	kagi := captureKagi(t, &got)
	defer kagi.Close()
	srv := newTestServer(kagi.URL)
	srv.cfg.kagiModel = "claude-5-sonnet"
	srv.cfg.kagiProfileID = "prof-123"
	rec := httptest.NewRecorder()
	srv.handleStories(rec, storyRequest(`{"childName":"하준","ageBand":"toddler","situationIds":["bedtime"]}`, "dev1"))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	if got["profile_id"] != "prof-123" {
		t.Errorf("profile_id = %v, want prof-123", got["profile_id"])
	}
	if _, ok := got["model"]; ok {
		t.Errorf("model must be omitted when a profile is configured")
	}
	if got["internet_access"] != false {
		t.Errorf("internet_access = %v, want false", got["internet_access"])
	}
	if got["personalization"] != false {
		t.Errorf("personalization = %v, want false", got["personalization"])
	}
}

func TestHandleStories_ValidatesRequest(t *testing.T) {
	srv := newTestServer("http://unused")
	req := storyRequest(`{"childName":""}`, "dev1")
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestHandleStories_RequiresDeviceHeader(t *testing.T) {
	srv := newTestServer("http://unused")
	req := storyRequest(`{"childName":"하준","situationIds":["bedtime"]}`, "") // no header
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 without device header", rec.Code)
	}
}

func TestHandleStories_WhitespaceChildNameIs400(t *testing.T) {
	srv := newTestServer("http://unused")
	req := storyRequest(`{"childName":"   ","situationIds":["bedtime"]}`, "dev1")
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestHandleStories_BlankSituationIdsIs400(t *testing.T) {
	srv := newTestServer("http://unused")
	req := storyRequest(`{"childName":"하준","situationIds":["",""]}`, "dev1")
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestHandleStories_KagiDownIs502AndRefunds(t *testing.T) {
	srv := newTestServer("http://127.0.0.1:0") // nothing listening
	req := storyRequest(`{"childName":"하준","situationIds":["bedtime"]}`, "dev1")
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", rec.Code)
	}
	// A failed generation must be refunded — the free slot is not consumed.
	if got := srv.quota.State("dev1").FreeUsed; got != 0 {
		t.Fatalf("free slot not refunded after failure: used = %d", got)
	}
}

func TestHandleCatalog(t *testing.T) {
	srv := newTestServer("http://unused")
	rec := httptest.NewRecorder()
	srv.handleCatalog(rec, httptest.NewRequest(http.MethodGet, "/v1/catalog/situations", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var doc map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &doc); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if doc["schemaVersion"].(float64) != 1 {
		t.Fatalf("schemaVersion = %v", doc["schemaVersion"])
	}
}

func TestExtractKagiText_Fallbacks(t *testing.T) {
	got, err := extractKagiText([]byte(`{"content":"hello"}`))
	if err != nil || got != "hello" {
		t.Fatalf("got %q err %v", got, err)
	}
	if _, err := extractKagiText([]byte(`{"other":1}`)); err == nil {
		t.Fatal("expected error when no text field present")
	}
}
