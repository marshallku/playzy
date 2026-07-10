package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
)

// StoryRequest is the provider-agnostic request from the app (ADR 0001). The
// backend owns the prompt; the app never builds one.
type StoryRequest struct {
	ChildName     string   `json:"childName"`
	AgeBand       string   `json:"ageBand"`
	SituationIDs  []string `json:"situationIds"`
	Interests     []string `json:"interests"`
	CompanionName string   `json:"companionName,omitempty"`
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
		pages := make([]StoryPage, 0, len(ms.Pages))
		for _, p := range ms.Pages {
			if strings.TrimSpace(p.Text) != "" {
				pages = append(pages, StoryPage{Text: strings.TrimSpace(p.Text)})
			}
		}
		if len(pages) > 0 {
			title := strings.TrimSpace(ms.Title)
			if title == "" {
				title = defaultTitle(req)
			}
			return Story{ID: id, Title: title, Pages: pages}
		}
		return safeStory(id, req)
	}
	// No JSON at all → treat the output as prose.
	return fallbackStory(id, modelText, req)
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

// fallbackStory splits prose into pages by blank lines so we never fail hard.
// Guarantees at least one non-empty page.
func fallbackStory(id, text string, req StoryRequest) Story {
	blocks := strings.Split(strings.TrimSpace(text), "\n\n")
	pages := make([]StoryPage, 0, len(blocks))
	for _, b := range blocks {
		b = strings.TrimSpace(b)
		if b != "" {
			pages = append(pages, StoryPage{Text: b})
		}
	}
	if len(pages) == 0 {
		pages = []StoryPage{{Text: fallbackText}}
	}
	return Story{ID: id, Title: defaultTitle(req), Pages: pages}
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
