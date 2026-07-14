package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"sync"
	"time"
)

// freeStoryLimit mirrors the app (docs/planning/20). The backend is the
// AUTHORITATIVE enforcer (ADR 0002); the app's local count is only a mirror.
const freeStoryLimit = 3

// reservationTTL bounds how long a pending hold survives without being committed
// or released. It comfortably exceeds the generation timeout (120s), so a
// legitimately in-flight generation never has its hold expire early; a crashed /
// abandoned request's hold auto-releases after this, so it is never a permanent
// charge (see the store docs and ADR 0002).
const reservationTTL = 10 * time.Minute

// maxGrant caps a single credit grant so a malformed/overflowing amount can't
// corrupt the credit invariant.
const maxGrant = 1000

var (
	// errQuotaExceeded is returned when a device is out of free stories and credits.
	errQuotaExceeded = errors.New("quota exceeded")
	// errCreditUnderflow means a credit reservation outlived its allowance (a
	// pathological clock jump). The hold is dropped rather than driving credits
	// negative; the caller treats it as "not charged".
	errCreditUnderflow = errors.New("credit underflow on commit")
	// errGrantConflict means an idempotency key was reused with a different
	// (device, amount) — the prior grant was for a different request, so we must
	// not silently acknowledge this one.
	errGrantConflict = errors.New("idempotency key reused with a different grant")
)

// reservation source: what a pending hold will consume when committed.
const (
	sourceFree   = "free"
	sourceCredit = "credit"
)

// quotaState is what the app reads to render remaining allowance. Fields are the
// COMMITTED ledger balance; CanGenerate is derived from that same balance so the
// response is internally consistent (pending in-flight holds are a within-request
// transient that only the authoritative Reserve acts on).
type quotaState struct {
	FreeUsed    int  `json:"freeUsed"`
	FreeLimit   int  `json:"freeLimit"`
	Credits     int  `json:"credits"`
	CanGenerate bool `json:"canGenerate"`
}

// clock returns the current time. Injectable so reservation TTL / expiry is
// deterministically testable.
type clock func() time.Time

// QuotaStore tracks per-device usage with a reserve→commit/release lifecycle so a
// failed or abandoned generation is never charged even across a crash (ADR 0002).
// Payment model is credit-packs-only (D1): free tier, then consumable credits.
//
// This is durable per-device accounting, NOT unbypassable enforcement:
// X-Device-Id is client-selected and resettable until accounts land (next WU).
type QuotaStore interface {
	State(deviceID string) (quotaState, error)
	// Reserve places a pending hold (free first, then a credit) and returns its
	// id; errQuotaExceeded when none is available. Nothing is charged yet.
	Reserve(deviceID string) (reservationID string, err error)
	// Commit consumes a hold after the story is delivered. Idempotent: a missing
	// reservation is a no-op.
	Commit(reservationID string) error
	// Release drops a hold after a failed/abandoned generation. Best-effort.
	Release(reservationID string)
	// AddCredits grants credits idempotently keyed on idempotencyKey (the verified
	// purchase id in production); reusing a key with a different (device, amount)
	// is errGrantConflict.
	AddCredits(deviceID string, n int, idempotencyKey string) error
}

// newReservationID is a unique, unguessable handle for a pending hold.
func newReservationID() string {
	var b [12]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "rsv_" + hex.EncodeToString([]byte(fallbackText))[:16]
	}
	return "rsv_" + hex.EncodeToString(b[:])
}

// ---- In-memory store (dev/test default) ---------------------------------

type memDevice struct {
	freeUsed int
	credits  int
}

type memReservation struct {
	deviceID string
	source   string
	at       time.Time
}

type memGrant struct {
	deviceID string
	amount   int
}

// InMemoryQuotaStore is the dev/test implementation. It mirrors the SQLite
// store's reservation lifecycle (a process restart wipes it, which is the
// correct non-durable semantics — the SQLite store is the durable one).
type InMemoryQuotaStore struct {
	mu     sync.Mutex
	now    clock
	dev    map[string]*memDevice
	res    map[string]memReservation
	grants map[string]memGrant
}

func NewInMemoryQuotaStore() *InMemoryQuotaStore {
	return newInMemoryQuotaStoreClock(time.Now)
}

func newInMemoryQuotaStoreClock(now clock) *InMemoryQuotaStore {
	return &InMemoryQuotaStore{
		now:    now,
		dev:    map[string]*memDevice{},
		res:    map[string]memReservation{},
		grants: map[string]memGrant{},
	}
}

// sweep drops holds older than the TTL. Caller holds the lock.
func (s *InMemoryQuotaStore) sweep() {
	cutoff := s.now().Add(-reservationTTL)
	for id, r := range s.res {
		if !r.at.After(cutoff) {
			delete(s.res, id)
		}
	}
}

// pending counts non-expired holds for a device by source. Caller holds the lock.
func (s *InMemoryQuotaStore) pending(deviceID string, cutoff time.Time) (free, credit int) {
	for _, r := range s.res {
		if r.deviceID != deviceID || !r.at.After(cutoff) {
			continue
		}
		if r.source == sourceFree {
			free++
		} else {
			credit++
		}
	}
	return
}

func (s *InMemoryQuotaStore) State(deviceID string) (quotaState, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	freeUsed, credits := 0, 0
	if d := s.dev[deviceID]; d != nil {
		freeUsed, credits = d.freeUsed, d.credits
	}
	return quotaState{
		FreeUsed:    freeUsed,
		FreeLimit:   freeStoryLimit,
		Credits:     credits,
		CanGenerate: freeUsed < freeStoryLimit || credits > 0,
	}, nil
}

func (s *InMemoryQuotaStore) Reserve(deviceID string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sweep()
	cutoff := s.now().Add(-reservationTTL)
	pendingFree, pendingCredit := s.pending(deviceID, cutoff)
	freeUsed, credits := 0, 0
	if d := s.dev[deviceID]; d != nil {
		freeUsed, credits = d.freeUsed, d.credits
	}
	var source string
	switch {
	case freeStoryLimit-freeUsed-pendingFree > 0:
		source = sourceFree
	case credits-pendingCredit > 0:
		source = sourceCredit
	default:
		return "", errQuotaExceeded
	}
	id := newReservationID()
	s.res[id] = memReservation{deviceID: deviceID, source: source, at: s.now()}
	return id, nil
}

func (s *InMemoryQuotaStore) Commit(reservationID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, ok := s.res[reservationID]
	if !ok {
		return nil // already committed/released — idempotent
	}
	d := s.dev[r.deviceID]
	if d == nil {
		d = &memDevice{}
		s.dev[r.deviceID] = d
	}
	switch r.source {
	case sourceFree:
		d.freeUsed++
	case sourceCredit:
		if d.credits <= 0 {
			delete(s.res, reservationID)
			return errCreditUnderflow
		}
		d.credits--
	}
	delete(s.res, reservationID)
	return nil
}

func (s *InMemoryQuotaStore) Release(reservationID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.res, reservationID)
}

func (s *InMemoryQuotaStore) AddCredits(deviceID string, n int, key string) error {
	if n <= 0 || n > maxGrant {
		return fmt.Errorf("invalid grant amount %d", n)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if g, ok := s.grants[key]; ok {
		if g.deviceID == deviceID && g.amount == n {
			return nil // idempotent replay
		}
		return errGrantConflict
	}
	s.grants[key] = memGrant{deviceID: deviceID, amount: n}
	d := s.dev[deviceID]
	if d == nil {
		d = &memDevice{}
		s.dev[deviceID] = d
	}
	d.credits += n
	return nil
}
