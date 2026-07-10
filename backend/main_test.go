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
		cfg:  config{kagiURL: kagiURL, timeout: 5 * time.Second},
		http: &http.Client{Timeout: 5 * time.Second},
	}
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
	req := httptest.NewRequest(http.MethodPost, "/v1/stories", strings.NewReader(body))
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

func TestHandleStories_ValidatesRequest(t *testing.T) {
	srv := newTestServer("http://unused")
	req := httptest.NewRequest(http.MethodPost, "/v1/stories", strings.NewReader(`{"childName":""}`))
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestHandleStories_WhitespaceChildNameIs400(t *testing.T) {
	srv := newTestServer("http://unused")
	req := httptest.NewRequest(http.MethodPost, "/v1/stories",
		strings.NewReader(`{"childName":"   ","situationIds":["bedtime"]}`))
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestHandleStories_BlankSituationIdsIs400(t *testing.T) {
	srv := newTestServer("http://unused")
	req := httptest.NewRequest(http.MethodPost, "/v1/stories",
		strings.NewReader(`{"childName":"하준","situationIds":["",""]}`))
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestHandleStories_KagiDownIs502(t *testing.T) {
	srv := newTestServer("http://127.0.0.1:0") // nothing listening
	body := `{"childName":"하준","situationIds":["bedtime"]}`
	req := httptest.NewRequest(http.MethodPost, "/v1/stories", strings.NewReader(body))
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", rec.Code)
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
