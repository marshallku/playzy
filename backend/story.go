package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"unicode"
)

// maxPageRunes caps a single page so a runaway model can't return a huge blob.
const maxPageRunes = 600

// unsafeTerms is a small STOPGAP denylist — NOT a substitute for the deferred
// output-moderation pass (README). If any surfaces in child-facing text, the
// story is replaced with the safe default rather than shown.
var unsafeTerms = []string{"죽여", "죽음", "살인", "칼로", "피가", "자살", "kill", "blood", "suicide"}

// sanitizeStoryText strips control characters, neutralizes line breaks, and
// caps length on model-produced text before it reaches a child.
func sanitizeStoryText(s string) string {
	s = strings.Map(func(r rune) rune {
		switch {
		case r == '\n' || r == '\r' || r == '\t':
			return ' '
		case unicode.IsControl(r):
			return -1
		default:
			return r
		}
	}, s)
	s = strings.TrimSpace(s)
	if r := []rune(s); len(r) > maxPageRunes {
		s = strings.TrimSpace(string(r[:maxPageRunes]))
	}
	return s
}

func containsUnsafe(s string) bool {
	low := strings.ToLower(s)
	for _, t := range unsafeTerms {
		if strings.Contains(low, t) {
			return true
		}
	}
	return false
}

// Character is an extra named figure to feature beyond the main child (등장인물).
type Character struct {
	Name string `json:"name"`
	Kind string `json:"kind"` // family|friend|animal|imaginary (whitelisted)
}

// StoryRequest is the provider-agnostic request from the app (ADR 0001). The
// backend owns the prompt; the app never builds one. The generation controls
// (Characters/Mood/Length, planning/40; funnel redesign planning/50) are optional
// and validated server-side — client-side limits are convenience, not the guard.
type StoryRequest struct {
	ChildName    string      `json:"childName"`
	AgeBand      string      `json:"ageBand"`
	SituationIDs []string    `json:"situationIds"`
	Interests    []string    `json:"interests"`
	Characters   []Character `json:"characters,omitempty"`
	Mood         string      `json:"mood,omitempty"`
	Length       string      `json:"length,omitempty"`
	// Topic is a free-text seed for tonight's story ("오늘의 이야기"). User-derived
	// and untrusted — sanitized like the other fields. A request is valid with a
	// topic OR at least one situationId (the app offers both).
	Topic string `json:"topic,omitempty"`
}

// Story is the structured result the app renders (title + pages).
type Story struct {
	ID        string      `json:"id"`
	Title     string      `json:"title"`
	Pages     []StoryPage `json:"pages"`
	CreatedAt string      `json:"createdAt,omitempty"`
}

type StoryPage struct {
	Text     string `json:"text"`
	ImageURL string `json:"imageUrl,omitempty"`
}

// modelStory is the strict JSON shape we ask the model to emit.
type modelStory struct {
	Title string `json:"title"`
	Pages []struct {
		Text string `json:"text"`
	} `json:"pages"`
}

// parseStory turns raw model output into a Story. The model is asked for strict
// JSON; if it wraps it in prose or fences, we extract the JSON object. If no
// usable JSON is found, we fall back to paragraph-splitting so a story is
// always returned rather than an error.
func parseStory(modelText string, req StoryRequest) Story {
	id := newStoryID()
	if ms, ok := extractModelStory(modelText); ok {
		// JSON was present: use its pages, or the safe default — never echo the
		// raw JSON back as story text.
		texts := make([]string, 0, len(ms.Pages))
		for _, p := range ms.Pages {
			texts = append(texts, p.Text)
		}
		return finalize(id, ms.Title, texts, req)
	}
	// No JSON at all → treat the output as prose (blank-line split).
	return fallbackStory(id, modelText, req)
}

// finalize sanitizes and safety-checks candidate story text, returning the
// safe default if nothing usable survives or an unsafe term appears anywhere.
func finalize(id, rawTitle string, rawPages []string, req StoryRequest) Story {
	title := sanitizeStoryText(rawTitle)
	pages := make([]StoryPage, 0, len(rawPages))
	unsafe := containsUnsafe(title)
	for _, t := range rawPages {
		clean := sanitizeStoryText(t)
		if clean == "" {
			continue
		}
		if containsUnsafe(clean) {
			unsafe = true
		}
		pages = append(pages, StoryPage{Text: clean})
	}
	if unsafe || len(pages) == 0 {
		return safeStory(id, req)
	}
	if title == "" {
		title = defaultTitle(req)
	}
	return Story{ID: id, Title: title, Pages: pages}
}

// extractModelStory finds the first {...} JSON object in the text and decodes
// it. Tolerates code fences and surrounding prose.
func extractModelStory(text string) (modelStory, bool) {
	start := strings.Index(text, "{")
	end := strings.LastIndex(text, "}")
	if start < 0 || end <= start {
		return modelStory{}, false
	}
	var ms modelStory
	if err := json.Unmarshal([]byte(text[start:end+1]), &ms); err != nil {
		return modelStory{}, false
	}
	return ms, true
}

// fallbackText is used when the model returns nothing usable, so a story is
// always non-empty (acceptance criterion) rather than a blank page.
const fallbackText = "포근한 밤이에요. 오늘도 참 잘했어요. 이제 편안히 잠들어요."

// fallbackStory splits prose into pages by blank lines, then sanitizes and
// safety-checks via finalize so we never fail hard or leak unsafe text.
func fallbackStory(id, text string, req StoryRequest) Story {
	blocks := strings.Split(strings.TrimSpace(text), "\n\n")
	return finalize(id, defaultTitle(req), blocks, req)
}

func defaultTitle(req StoryRequest) string {
	name := req.ChildName
	if name == "" {
		name = "우리 아이"
	}
	return fmt.Sprintf("%s의 이야기", name)
}

// safeStory returns a gentle, always-non-empty story when the model output is
// unusable — without echoing raw JSON to a child.
func safeStory(id string, req StoryRequest) Story {
	return Story{ID: id, Title: defaultTitle(req), Pages: []StoryPage{{Text: fallbackText}}}
}

// newStoryID is unique per generation: each generated story is a distinct
// creative artifact (two stories from the same request differ), so identity
// must not collide when the library persists them.
func newStoryID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "st_" + hex.EncodeToString([]byte(fallbackText))[:16]
	}
	return "st_" + hex.EncodeToString(b[:])
}
