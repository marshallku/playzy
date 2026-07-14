package main

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
)

// productCredits maps a purchasable product id to the story credits it grants.
// Single source of truth; a product not listed here is never granted (logged for
// manual reconciliation). Consumable credit packs only — no subscriptions (D1).
var productCredits = map[string]int{
	"credits_10": 10,
}

// rcWebhookBody is the RevenueCat webhook envelope: {"api_version": "...",
// "event": {...}}. We consume only the event subset we act on.
type rcWebhookBody struct {
	Event rcEvent `json:"event"`
}

// rcEvent is the subset of a RevenueCat webhook event this handler needs. See
// https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields.
type rcEvent struct {
	Type          string `json:"type"`
	ID            string `json:"id"`             // event id — NOT the purchase identity
	AppID         string `json:"app_id"`         // RevenueCat app id (project isolation)
	AppUserID     string `json:"app_user_id"`    // the subject (device id now, account id later)
	ProductID     string `json:"product_id"`     // e.g. "credits_10"
	Store         string `json:"store"`          // "APP_STORE", "PLAY_STORE", …
	Environment   string `json:"environment"`    // "PRODUCTION" | "SANDBOX"
	TransactionID string `json:"transaction_id"` // store transaction id — the grant idempotency key
}

// handleRevenueCatWebhook is the production purchase path (POST
// /v1/webhooks/revenuecat) that replaces the dev /v1/credits admin stub. When a
// consumable credit pack is purchased, RevenueCat delivers a shared-secret-
// authenticated event; we grant credits idempotently on the store transaction id.
//
// It returns 200 on every *handled* case — including intentional no-ops (foreign
// app, sandbox, unknown product, non-purchase event) — because RevenueCat retries
// any non-2xx up to five times. Only a transient store failure returns 5xx to
// earn a retry; a malformed/unattributable event is acknowledged and logged so a
// real purchase can be reconciled via RevenueCat's manual replay or /v1/credits.
func (s *server) handleRevenueCatWebhook(w http.ResponseWriter, r *http.Request) {
	if s.cfg.revenueCatWebhookAuth == "" {
		httpError(w, http.StatusNotFound, "not found")
		return
	}
	// RevenueCat sends the configured shared secret verbatim in the Authorization
	// header (its documented webhook auth). Constant-time compare avoids leaking the
	// secret through timing.
	got := []byte(r.Header.Get("Authorization"))
	want := []byte(s.cfg.revenueCatWebhookAuth)
	if subtle.ConstantTimeCompare(got, want) != 1 {
		httpError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MiB, matching the story handler
	var body rcWebhookBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		// Unparseable/oversized body: a retry can't fix genuine malformation, so ack
		// (200) and log at ERROR rather than making RevenueCat retry 5× for nothing.
		log.Printf("rc webhook: ERROR unparseable body, no grant: %v", err)
		writeWebhookOK(w)
		return
	}
	ev := body.Event

	// Only consumable purchases grant credits. Everything else (subscription
	// lifecycle, cancellations, transfers, …) is acknowledged and ignored: we sell
	// no subscriptions, and consumable credits are non-revocable in v1 — a refund
	// does not claw back already-granted credits (a bounded, explicit business
	// choice; revisit if refund abuse shows up).
	if ev.Type != "NON_RENEWING_PURCHASE" {
		writeWebhookOK(w)
		return
	}

	// Production isolation: a correctly-authenticated SANDBOX or foreign-app event
	// must never mint real credits. Bind to the configured app + production
	// environment; sandbox is accepted only behind an explicit dev flag so
	// local/sandbox testing still works.
	// Accept PRODUCTION always; SANDBOX only behind the dev flag; never any other or
	// empty environment — a correctly-authenticated non-production event must not mint
	// real credits, and the flag must widen the allow-list by exactly SANDBOX, not
	// disable environment validation.
	switch {
	case strings.EqualFold(ev.Environment, "PRODUCTION"):
	case strings.EqualFold(ev.Environment, "SANDBOX") && s.cfg.revenueCatAllowSandbox:
	default:
		log.Printf("rc webhook: ignoring non-production purchase env=%q txn=%q", ev.Environment, ev.TransactionID)
		writeWebhookOK(w)
		return
	}
	if s.cfg.revenueCatAppID != "" && ev.AppID != s.cfg.revenueCatAppID {
		log.Printf("rc webhook: ignoring foreign app_id=%q (want %q) txn=%q", ev.AppID, s.cfg.revenueCatAppID, ev.TransactionID)
		writeWebhookOK(w)
		return
	}
	if !isSupportedStore(ev.Store) {
		log.Printf("rc webhook: ignoring unsupported store=%q txn=%q", ev.Store, ev.TransactionID)
		writeWebhookOK(w)
		return
	}

	// Purchase identity is the store transaction id. The event id is NOT a safe
	// fallback (distinct events can concern one purchase), so an absent transaction
	// id must never grant.
	txn := strings.TrimSpace(ev.TransactionID)
	if txn == "" {
		log.Printf("rc webhook: ERROR purchase missing transaction_id, no grant: subject=%q product=%q event_id=%q", ev.AppUserID, ev.ProductID, ev.ID)
		writeWebhookOK(w)
		return
	}

	// app_user_id is client-influenced, so apply the same bound+charset contract as
	// X-Device-Id — a crafted value must not write an unbounded durable-store key.
	subject := strings.TrimSpace(ev.AppUserID)
	if subject == "" || len(subject) > maxDeviceIDLen || !isPrintableASCII(subject) {
		log.Printf("rc webhook: ERROR unattributable/malformed app_user_id=%q txn=%q, no grant", ev.AppUserID, txn)
		writeWebhookOK(w)
		return
	}

	credits, ok := productCredits[ev.ProductID]
	if !ok {
		// A real paid purchase for a product we don't map: do not retry (a config
		// gap, not transient). Logged at ERROR with the txn id so it can be
		// reconciled via RevenueCat's manual replay or the admin /v1/credits path.
		log.Printf("rc webhook: ERROR unknown product_id=%q txn=%q subject=%q, no grant (reconcile manually)", ev.ProductID, txn, subject)
		writeWebhookOK(w)
		return
	}

	if err := s.quota.AddCredits(subject, credits, txn); err != nil {
		if errors.Is(err, errGrantConflict) {
			// Same txn id previously granted a different (subject, amount): a replayed
			// or edited delivery. Non-retryable, so ack; log for tuning.
			log.Printf("rc webhook: WARN grant conflict txn=%q subject=%q product=%q", txn, subject, ev.ProductID)
			writeWebhookOK(w)
			return
		}
		// Transient store/db failure — 5xx so RevenueCat retries.
		log.Printf("rc webhook: add credits: %v", err)
		httpError(w, http.StatusInternalServerError, "credit grant failed")
		return
	}
	log.Printf("rc webhook: granted %d credits subject=%q txn=%q product=%q", credits, subject, txn, ev.ProductID)
	writeWebhookOK(w)
}

// isSupportedStore restricts grants to the stores we actually sell through. iOS is
// the launch target; MAC_APP_STORE is accepted for a shared Apple build. Play/web
// join here when those gateways ship (they route through the same handler).
func isSupportedStore(store string) bool {
	switch strings.ToUpper(strings.TrimSpace(store)) {
	case "APP_STORE", "MAC_APP_STORE":
		return true
	default:
		return false
	}
}

func writeWebhookOK(w http.ResponseWriter) {
	_ = writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
