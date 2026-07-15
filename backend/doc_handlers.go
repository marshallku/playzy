package main

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"unicode/utf8"
)

// Account-scoped profile/roster sync (WU6). All require a valid session (account
// scope); disabled (404) when auth isn't configured. The document is an opaque
// UTF-8 string — the backend never parses the app schema. Arrival-order-wins.

func (s *server) handleGetProfile(w http.ResponseWriter, r *http.Request) { s.handleGetDoc(w, r, docProfile) }
func (s *server) handlePutProfile(w http.ResponseWriter, r *http.Request) { s.handlePutDoc(w, r, docProfile) }
func (s *server) handleGetRoster(w http.ResponseWriter, r *http.Request)  { s.handleGetDoc(w, r, docRoster) }
func (s *server) handlePutRoster(w http.ResponseWriter, r *http.Request)  { s.handlePutDoc(w, r, docRoster) }

func (s *server) handleGetDoc(w http.ResponseWriter, r *http.Request, kind docKind) {
	acct, ok := s.requireAccount(w, r)
	if !ok {
		return
	}
	doc, found, err := s.docs.GetDoc(acct.ID, kind)
	if err != nil {
		log.Printf("get doc %s: %v", kind, err)
		httpError(w, http.StatusInternalServerError, "could not read document")
		return
	}
	// Absent → {"doc": null} so the client can distinguish "never synced" from empty.
	if !found {
		writeJSON(w, http.StatusOK, map[string]any{"doc": nil})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"doc": doc})
}

func (s *server) handlePutDoc(w http.ResponseWriter, r *http.Request, kind docKind) {
	acct, ok := s.requireAccount(w, r)
	if !ok {
		return
	}
	// Body cap allows for the worst-case JSON escaping of a maxDocBytes document:
	// a control byte becomes a 6-char \uXXXX escape, so budget 6× plus overhead. A
	// legit maxDocBytes doc must never trip this — the semantic cap is enforced on the
	// decoded length below (413).
	r.Body = http.MaxBytesReader(w, r.Body, maxDocBytes*6+4096)
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			httpError(w, http.StatusRequestEntityTooLarge, "request body too large")
			return
		}
		httpError(w, http.StatusBadRequest, "could not read request body")
		return
	}
	// Validate UTF-8 on the RAW bytes: json.Unmarshal silently replaces malformed
	// UTF-8 inside a string with U+FFFD, so a post-decode check would never catch it.
	// Checking the raw body actually rejects it (the stored doc must be verbatim UTF-8).
	if !utf8.Valid(raw) {
		httpError(w, http.StatusBadRequest, "request must be valid UTF-8")
		return
	}
	var body struct {
		Doc *string `json:"doc"`
	}
	// json.Unmarshal errors on trailing content after the top-level value, so a
	// separate trailing-data check isn't needed.
	if err := json.Unmarshal(raw, &body); err != nil || body.Doc == nil {
		httpError(w, http.StatusBadRequest, "doc (string) is required")
		return
	}
	doc := *body.Doc
	if len(doc) > maxDocBytes {
		httpError(w, http.StatusRequestEntityTooLarge, "document too large")
		return
	}
	if err := s.docs.PutDoc(acct.ID, kind, doc, s.now()); err != nil {
		log.Printf("put doc %s: %v", kind, err)
		httpError(w, http.StatusInternalServerError, "could not save document")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
