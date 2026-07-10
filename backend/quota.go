package main

import (
	"errors"
	"sync"
)

// freeStoryLimit mirrors the app (docs/planning/20). The backend is the
// AUTHORITATIVE enforcer (ADR 0002); the app's local count is only a mirror.
const freeStoryLimit = 3

// errQuotaExceeded is returned when a device is out of free stories and credits.
var errQuotaExceeded = errors.New("quota exceeded")

// charge records what a generation was billed against, so it can be refunded if
// generation then fails (reserve-then-generate).
type charge int

const (
	chargeFree charge = iota
	chargeCredit
)

// quotaState is what the app reads to render remaining allowance.
type quotaState struct {
	FreeUsed    int  `json:"freeUsed"`
	FreeLimit   int  `json:"freeLimit"`
	Credits     int  `json:"credits"`
	CanGenerate bool `json:"canGenerate"`
}

// QuotaStore tracks per-device usage. Payment model is credit-packs-only
// (D1): free tier, then consumable credits — no subscription.
type QuotaStore interface {
	State(deviceID string) quotaState
	// Reserve charges a free slot first, then a credit; errQuotaExceeded if none.
	Reserve(deviceID string) (charge, error)
	Refund(deviceID string, c charge)
	AddCredits(deviceID string, n int)
}

// device holds one device's counters.
type device struct {
	used    int
	credits int
}

// InMemoryQuotaStore is the dev implementation. Production must back this with a
// shared store (Redis/DB) so quota survives restarts and scales horizontally —
// documented in backend/README.md.
type InMemoryQuotaStore struct {
	mu      sync.Mutex
	devices map[string]*device
}

func NewInMemoryQuotaStore() *InMemoryQuotaStore {
	return &InMemoryQuotaStore{devices: map[string]*device{}}
}

func (s *InMemoryQuotaStore) get(deviceID string) *device {
	d, ok := s.devices[deviceID]
	if !ok {
		d = &device{}
		s.devices[deviceID] = d
	}
	return d
}

func (s *InMemoryQuotaStore) State(deviceID string) quotaState {
	s.mu.Lock()
	defer s.mu.Unlock()
	d := s.get(deviceID)
	return quotaState{
		FreeUsed:    d.used,
		FreeLimit:   freeStoryLimit,
		Credits:     d.credits,
		CanGenerate: d.used < freeStoryLimit || d.credits > 0,
	}
}

func (s *InMemoryQuotaStore) Reserve(deviceID string) (charge, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d := s.get(deviceID)
	if d.used < freeStoryLimit {
		d.used++
		return chargeFree, nil
	}
	if d.credits > 0 {
		d.credits--
		return chargeCredit, nil
	}
	return chargeFree, errQuotaExceeded
}

func (s *InMemoryQuotaStore) Refund(deviceID string, c charge) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d := s.get(deviceID)
	switch c {
	case chargeFree:
		if d.used > 0 {
			d.used--
		}
	case chargeCredit:
		d.credits++
	}
}

func (s *InMemoryQuotaStore) AddCredits(deviceID string, n int) {
	if n <= 0 {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.get(deviceID).credits += n
}
