package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestInMemoryQuotaStore_FreeThenCreditsThenExceeded(t *testing.T) {
	s := NewInMemoryQuotaStore()

	// Free tier: freeStoryLimit reservations succeed as chargeFree.
	for i := 0; i < freeStoryLimit; i++ {
		c, err := s.Reserve("d")
		if err != nil || c != chargeFree {
			t.Fatalf("free reserve %d: c=%v err=%v", i, c, err)
		}
	}
	// Out of free, no credits → exceeded.
	if _, err := s.Reserve("d"); err != errQuotaExceeded {
		t.Fatalf("expected quota exceeded, got %v", err)
	}

	// Add credits → reservations resume as chargeCredit.
	s.AddCredits("d", 2)
	c, err := s.Reserve("d")
	if err != nil || c != chargeCredit {
		t.Fatalf("credit reserve: c=%v err=%v", c, err)
	}
	st := s.State("d")
	if st.Credits != 1 || st.FreeUsed != freeStoryLimit {
		t.Fatalf("state = %+v", st)
	}
}

func TestInMemoryQuotaStore_RefundRestores(t *testing.T) {
	s := NewInMemoryQuotaStore()
	c, _ := s.Reserve("d") // chargeFree, used=1
	s.Refund("d", c)
	if u := s.State("d").FreeUsed; u != 0 {
		t.Fatalf("free refund: used = %d", u)
	}

	s.AddCredits("d", 1)
	// Exhaust free, then reserve a credit and refund it.
	for i := 0; i < freeStoryLimit; i++ {
		s.Reserve("d")
	}
	cc, _ := s.Reserve("d") // chargeCredit, credits 1->0
	s.Refund("d", cc)
	if cr := s.State("d").Credits; cr != 1 {
		t.Fatalf("credit refund: credits = %d", cr)
	}
}

func TestInMemoryQuotaStore_DevicesAreIsolated(t *testing.T) {
	s := NewInMemoryQuotaStore()
	s.Reserve("a")
	if s.State("b").FreeUsed != 0 {
		t.Fatal("device b should be unaffected by device a")
	}
}

func TestHandleQuota(t *testing.T) {
	srv := newTestServer("http://unused")
	srv.quota.AddCredits("dev1", 5)
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

func TestHandleStories_QuotaExceededIs402(t *testing.T) {
	srv := newTestServer("http://unused")
	// Exhaust the free tier for this device.
	for i := 0; i < freeStoryLimit; i++ {
		srv.quota.Reserve("dev1")
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
	if srv.quota.State("dev1").Credits != 10 {
		t.Fatalf("credits = %d", srv.quota.State("dev1").Credits)
	}

	// Non-positive amount → 400.
	badRec := httptest.NewRecorder()
	srv.handleGrantCredits(badRec, grantReq("dev1", "test-admin", `{"amount":0}`))
	if badRec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", badRec.Code)
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
	if srv.quota.State("dev1").Credits != 0 {
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
