package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const testWebhookAuth = "rc-shared-secret"

// newWebhookServer builds a server with the RevenueCat webhook enabled and the
// given store. Sandbox is disabled (production-only) unless a test flips it.
func newWebhookServer(store QuotaStore) *server {
	return &server{
		cfg: config{
			quotaStore:            "memory",
			revenueCatWebhookAuth: testWebhookAuth,
		},
		quota: store,
	}
}

// rcEventJSON builds a RevenueCat webhook body from a valid consumable-purchase
// default, applying overrides. A nil override value deletes that field.
func rcEventJSON(overrides map[string]any) string {
	ev := map[string]any{
		"type":           "NON_RENEWING_PURCHASE",
		"id":             "evt-1",
		"app_user_id":    "device-abc",
		"product_id":     "credits_10",
		"store":          "APP_STORE",
		"environment":    "PRODUCTION",
		"transaction_id": "txn-1",
	}
	for k, v := range overrides {
		if v == nil {
			delete(ev, k)
		} else {
			ev[k] = v
		}
	}
	b, _ := json.Marshal(map[string]any{"api_version": "1.0", "event": ev})
	return string(b)
}

func webhookRequest(body, auth string) *http.Request {
	req := httptest.NewRequest(http.MethodPost, "/v1/webhooks/revenuecat", strings.NewReader(body))
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	return req
}

func creditsOf(t *testing.T, store QuotaStore, subject string) int {
	t.Helper()
	st, err := store.State(subject)
	if err != nil {
		t.Fatalf("state(%q): %v", subject, err)
	}
	return st.Credits
}

// addCreditsFailStore forces AddCredits to return a (non-conflict) error so the
// transient-failure → 500 branch can be exercised. Other methods delegate to the
// embedded real store.
type addCreditsFailStore struct {
	QuotaStore
	err error
}

func (f addCreditsFailStore) AddCredits(string, int, string) error { return f.err }

func TestRCWebhook_ValidPurchaseGrants(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := newWebhookServer(store)
	rec := httptest.NewRecorder()
	srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(nil), testWebhookAuth))

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, want 200; body=%s", rec.Code, rec.Body.String())
	}
	if got := creditsOf(t, store, "device-abc"); got != 10 {
		t.Fatalf("credits = %d, want 10", got)
	}
}

func TestRCWebhook_DuplicateDeliveryIsIdempotent(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := newWebhookServer(store)
	body := rcEventJSON(nil)

	for i := 0; i < 3; i++ {
		rec := httptest.NewRecorder()
		srv.handleRevenueCatWebhook(rec, webhookRequest(body, testWebhookAuth))
		if rec.Code != http.StatusOK {
			t.Fatalf("delivery %d: code = %d, want 200", i, rec.Code)
		}
	}
	if got := creditsOf(t, store, "device-abc"); got != 10 {
		t.Fatalf("credits = %d after 3 identical deliveries, want 10 (idempotent)", got)
	}
}

func TestRCWebhook_WrongAuthIs401(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := newWebhookServer(store)
	for _, auth := range []string{"", "wrong-secret"} {
		rec := httptest.NewRecorder()
		srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(nil), auth))
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("auth=%q: code = %d, want 401", auth, rec.Code)
		}
	}
	if got := creditsOf(t, store, "device-abc"); got != 0 {
		t.Fatalf("credits = %d, want 0 (no grant on bad auth)", got)
	}
}

func TestRCWebhook_DisabledWhenNoSecretIs404(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := &server{cfg: config{quotaStore: "memory"}, quota: store} // no webhook secret
	rec := httptest.NewRecorder()
	// Even a valid-looking body + Authorization must not enable a disabled endpoint.
	srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(nil), "anything"))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("code = %d, want 404 (endpoint disabled)", rec.Code)
	}
}

// acked-but-not-granted cases: every one returns 200 (so RevenueCat stops
// retrying) yet writes zero credits.
func TestRCWebhook_AckedNoGrantCases(t *testing.T) {
	cases := []struct {
		name      string
		overrides map[string]any
	}{
		{"unknown product", map[string]any{"product_id": "credits_999"}},
		{"non-purchase event", map[string]any{"type": "CANCELLATION"}},
		{"subscription initial purchase", map[string]any{"type": "INITIAL_PURCHASE"}},
		{"sandbox environment", map[string]any{"environment": "SANDBOX"}},
		{"unsupported store", map[string]any{"store": "STRIPE"}},
		{"missing transaction_id", map[string]any{"transaction_id": nil}},
		{"blank transaction_id", map[string]any{"transaction_id": "   "}},
		{"missing app_user_id", map[string]any{"app_user_id": nil}},
		{"non-ascii app_user_id", map[string]any{"app_user_id": "디바이스"}},
		{"oversized app_user_id", map[string]any{"app_user_id": strings.Repeat("a", maxDeviceIDLen+1)}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			store := NewInMemoryQuotaStore()
			srv := newWebhookServer(store)
			rec := httptest.NewRecorder()
			srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(c.overrides), testWebhookAuth))
			if rec.Code != http.StatusOK {
				t.Fatalf("code = %d, want 200 (acked no-op); body=%s", rec.Code, rec.Body.String())
			}
			// The default subject gets nothing. (Cases that null the subject can't be
			// keyed anyway; this asserts the default holder is untouched.)
			if got := creditsOf(t, store, "device-abc"); got != 0 {
				t.Fatalf("%s: credits = %d, want 0", c.name, got)
			}
		})
	}
}

func TestRCWebhook_SandboxAcceptedWithDevFlag(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := newWebhookServer(store)
	srv.cfg.revenueCatAllowSandbox = true
	rec := httptest.NewRecorder()
	srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(map[string]any{"environment": "SANDBOX"}), testWebhookAuth))
	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, want 200", rec.Code)
	}
	if got := creditsOf(t, store, "device-abc"); got != 10 {
		t.Fatalf("credits = %d, want 10 (sandbox accepted under dev flag)", got)
	}
}

func TestRCWebhook_ForeignAppIDIgnored(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := newWebhookServer(store)
	srv.cfg.revenueCatAppID = "app_ours"
	rec := httptest.NewRecorder()
	srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(map[string]any{"app_id": "app_someone_else"}), testWebhookAuth))
	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, want 200 (acked)", rec.Code)
	}
	if got := creditsOf(t, store, "device-abc"); got != 0 {
		t.Fatalf("credits = %d, want 0 (foreign app ignored)", got)
	}
	// Same event with the matching app id DOES grant.
	rec = httptest.NewRecorder()
	srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(map[string]any{"app_id": "app_ours"}), testWebhookAuth))
	if got := creditsOf(t, store, "device-abc"); got != 10 {
		t.Fatalf("credits = %d, want 10 (matching app id grants)", got)
	}
}

// Unparseable body is acknowledged with 200 (a retry can't fix malformation) — never
// a non-2xx that would make RevenueCat retry 5×.
func TestRCWebhook_MalformedJSONIsAcked(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := newWebhookServer(store)
	rec := httptest.NewRecorder()
	srv.handleRevenueCatWebhook(rec, webhookRequest("{not json", testWebhookAuth))
	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, want 200 (malformed acked, not retried)", rec.Code)
	}
}

// With the sandbox dev flag on, only SANDBOX is additionally allowed — an empty or
// unknown environment must still be rejected (the flag widens by exactly SANDBOX, it
// does not disable environment validation).
func TestRCWebhook_UnknownEnvRejectedEvenWithSandboxFlag(t *testing.T) {
	for _, env := range []string{"", "STAGING", "PROD"} {
		store := NewInMemoryQuotaStore()
		srv := newWebhookServer(store)
		srv.cfg.revenueCatAllowSandbox = true
		rec := httptest.NewRecorder()
		srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(map[string]any{"environment": env}), testWebhookAuth))
		if rec.Code != http.StatusOK {
			t.Fatalf("env=%q: code = %d, want 200 (acked)", env, rec.Code)
		}
		if got := creditsOf(t, store, "device-abc"); got != 0 {
			t.Fatalf("env=%q: credits = %d, want 0 (only PRODUCTION/SANDBOX accepted)", env, got)
		}
	}
}

// A conflict (same txn id already granted a different amount) is acknowledged with
// 200 — never retried — and the original grant is preserved.
func TestRCWebhook_GrantConflictIsAcked(t *testing.T) {
	store := NewInMemoryQuotaStore()
	srv := newWebhookServer(store)
	// Pre-seed the same transaction id with a different amount, forcing errGrantConflict.
	if err := store.AddCredits("device-abc", 5, "txn-1"); err != nil {
		t.Fatalf("seed: %v", err)
	}
	rec := httptest.NewRecorder()
	srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(nil), testWebhookAuth))
	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, want 200 (conflict acked)", rec.Code)
	}
	if got := creditsOf(t, store, "device-abc"); got != 5 {
		t.Fatalf("credits = %d, want 5 (original grant preserved, conflict not applied)", got)
	}
}

// A transient store failure returns 5xx so RevenueCat retries.
func TestRCWebhook_TransientStoreErrorIs500(t *testing.T) {
	store := addCreditsFailStore{QuotaStore: NewInMemoryQuotaStore(), err: errors.New("db down")}
	srv := newWebhookServer(store)
	rec := httptest.NewRecorder()
	srv.handleRevenueCatWebhook(rec, webhookRequest(rcEventJSON(nil), testWebhookAuth))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("code = %d, want 500 (transient failure earns a retry)", rec.Code)
	}
}
