package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// mustState reads a store's state, failing the test on error.
func mustState(t *testing.T, s QuotaStore, deviceID string) quotaState {
	t.Helper()
	st, err := s.State(deviceID)
	if err != nil {
		t.Fatalf("State(%q): %v", deviceID, err)
	}
	return st
}

// reserveCommit reserves then commits one story, as a successful generation does.
func reserveCommit(t *testing.T, s QuotaStore, deviceID string) error {
	t.Helper()
	id, err := s.Reserve(deviceID)
	if err != nil {
		return err
	}
	if err := s.Commit(id); err != nil {
		t.Fatalf("Commit: %v", err)
	}
	return nil
}

func TestHandleQuota(t *testing.T) {
	srv := newTestServer("http://unused")
	if err := srv.quota.AddCredits("dev1", 5, "k1"); err != nil {
		t.Fatalf("AddCredits: %v", err)
	}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/quota", nil)
	req.Header.Set(deviceHeader, "dev1")

	srv.handleQuota(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var st quotaState
	_ = json.Unmarshal(rec.Body.Bytes(), &st)
	if st.Credits != 5 || st.FreeLimit != freeStoryLimit || !st.CanGenerate {
		t.Fatalf("state = %+v", st)
	}
}

func TestHandleQuota_RejectsMalformedDeviceID(t *testing.T) {
	srv := newTestServer("http://unused")
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/quota", nil)
	req.Header.Set(deviceHeader, strings.Repeat("x", maxDeviceIDLen+1))

	srv.handleQuota(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 for oversized device id", rec.Code)
	}
}

func TestHandleStories_QuotaExceededIs402(t *testing.T) {
	srv := newTestServer("http://unused")
	// Exhaust the free tier for this device (holds alone exhaust availability).
	for i := 0; i < freeStoryLimit; i++ {
		if err := reserveCommit(t, srv.quota, "dev1"); err != nil {
			t.Fatalf("setup reserve %d: %v", i, err)
		}
	}
	req := storyRequest(`{"childName":"하준","situationIds":["bedtime"]}`, "dev1")
	rec := httptest.NewRecorder()

	srv.handleStories(rec, req)

	if rec.Code != http.StatusPaymentRequired {
		t.Fatalf("status = %d, want 402", rec.Code)
	}
}

func grantReq(deviceID, adminToken, body string) *http.Request {
	req := httptest.NewRequest(http.MethodPost, "/v1/credits", strings.NewReader(body))
	if deviceID != "" {
		req.Header.Set(deviceHeader, deviceID)
	}
	if adminToken != "" {
		req.Header.Set("X-Admin-Token", adminToken)
	}
	return req
}

func TestHandleGrantCredits_WithAdminToken(t *testing.T) {
	srv := newTestServer("http://unused")
	rec := httptest.NewRecorder()
	srv.handleGrantCredits(rec, grantReq("dev1", "test-admin", `{"amount":10}`))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	if c := mustState(t, srv.quota, "dev1").Credits; c != 10 {
		t.Fatalf("credits = %d", c)
	}

	// Non-positive amount → 400.
	badRec := httptest.NewRecorder()
	srv.handleGrantCredits(badRec, grantReq("dev1", "test-admin", `{"amount":0}`))
	if badRec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", badRec.Code)
	}

	// Over-cap amount → 400 (can't overflow the credit invariant).
	bigRec := httptest.NewRecorder()
	srv.handleGrantCredits(bigRec, grantReq("dev1", "test-admin", `{"amount":100000}`))
	if bigRec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 for over-cap amount", bigRec.Code)
	}
}

func TestHandleGrantCredits_IdempotencyKeyRepeatsGrantOnce(t *testing.T) {
	srv := newTestServer("http://unused")
	body := `{"amount":5,"idempotencyKey":"purchase-123"}`
	for i := 0; i < 3; i++ {
		rec := httptest.NewRecorder()
		srv.handleGrantCredits(rec, grantReq("dev1", "test-admin", body))
		if rec.Code != http.StatusOK {
			t.Fatalf("grant %d status = %d", i, rec.Code)
		}
	}
	// Three identical (idempotent) webhook deliveries grant the pack exactly once.
	if c := mustState(t, srv.quota, "dev1").Credits; c != 5 {
		t.Fatalf("credits = %d, want 5 (idempotent)", c)
	}

	// Same key, different amount → 409 conflict, no additional grant.
	rec := httptest.NewRecorder()
	srv.handleGrantCredits(rec, grantReq("dev1", "test-admin", `{"amount":9,"idempotencyKey":"purchase-123"}`))
	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", rec.Code)
	}
	if c := mustState(t, srv.quota, "dev1").Credits; c != 5 {
		t.Fatalf("credits = %d after conflict, want 5", c)
	}
}

func TestHandleGrantCredits_KeylessRequiresKeyOutsideDev(t *testing.T) {
	srv := newTestServer("http://unused")
	// Simulate a production (durable) deployment: a keyless grant must be rejected
	// so a retried malformed webhook can't re-credit.
	srv.cfg.quotaStore = "sqlite"
	rec := httptest.NewRecorder()
	srv.handleGrantCredits(rec, grantReq("dev1", "test-admin", `{"amount":5}`))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (idempotencyKey required outside dev)", rec.Code)
	}
	// With a key it succeeds.
	okRec := httptest.NewRecorder()
	srv.handleGrantCredits(okRec, grantReq("dev1", "test-admin", `{"amount":5,"idempotencyKey":"p1"}`))
	if okRec.Code != http.StatusOK {
		t.Fatalf("keyed grant status = %d, want 200", okRec.Code)
	}
}

func TestHandleGrantCredits_RejectsWithoutAdminToken(t *testing.T) {
	srv := newTestServer("http://unused")
	rec := httptest.NewRecorder()
	// A client without the admin token must not be able to grant credits.
	srv.handleGrantCredits(rec, grantReq("dev1", "", `{"amount":999}`))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", rec.Code)
	}
	if c := mustState(t, srv.quota, "dev1").Credits; c != 0 {
		t.Fatal("credits granted without admin token")
	}
}

func TestHandleGrantCredits_DisabledWhenNoAdminToken(t *testing.T) {
	srv := newTestServer("http://unused")
	srv.cfg.adminToken = "" // endpoint disabled entirely
	rec := httptest.NewRecorder()
	srv.handleGrantCredits(rec, grantReq("dev1", "anything", `{"amount":5}`))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}

func TestNewQuotaStore_FailClosed(t *testing.T) {
	// Unset selector → fatal misconfig (never a silent data-losing fallback).
	if _, _, err := newQuotaStore(config{}); err == nil {
		t.Fatal("unset PLAYZY_QUOTA_STORE must be an error")
	}
	// Unknown selector → error.
	if _, _, err := newQuotaStore(config{quotaStore: "postgres"}); err == nil {
		t.Fatal("unknown store must be an error")
	}
	// sqlite without a path → error.
	if _, _, err := newQuotaStore(config{quotaStore: "sqlite"}); err == nil {
		t.Fatal("sqlite without PLAYZY_DB_PATH must be an error")
	}
	// memory → ok.
	st, closeStore, err := newQuotaStore(config{quotaStore: "memory"})
	if err != nil || st == nil {
		t.Fatalf("memory store: st=%v err=%v", st, err)
	}
	_ = closeStore()
}
