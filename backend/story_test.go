package main

import (
	"strings"
	"testing"
)

var sampleReq = StoryRequest{
	ChildName:    "하준",
	AgeBand:      "toddler",
	SituationIDs: []string{"bedtime"},
}

func TestParseStory_StrictJSON(t *testing.T) {
	text := `{"title": "하준의 밤", "pages": [{"text": "옛날 옛적에"}, {"text": "잘 자요"}]}`
	story := parseStory(text, sampleReq)
	if story.Title != "하준의 밤" {
		t.Fatalf("title = %q", story.Title)
	}
	if len(story.Pages) != 2 || story.Pages[0].Text != "옛날 옛적에" {
		t.Fatalf("pages = %+v", story.Pages)
	}
}

func TestParseStory_JSONWrappedInProse(t *testing.T) {
	text := "물론이죠! 여기 동화입니다:\n```json\n{\"title\":\"제목\",\"pages\":[{\"text\":\"한 페이지\"}]}\n```\n즐겁게 읽어주세요."
	story := parseStory(text, sampleReq)
	if story.Title != "제목" || len(story.Pages) != 1 {
		t.Fatalf("unexpected: %+v", story)
	}
}

func TestParseStory_FallbackOnProse(t *testing.T) {
	text := "첫 번째 문단이에요.\n\n두 번째 문단이에요."
	story := parseStory(text, sampleReq)
	if len(story.Pages) != 2 {
		t.Fatalf("expected 2 fallback pages, got %d", len(story.Pages))
	}
	if story.Title == "" {
		t.Fatal("fallback should still produce a title")
	}
}

func TestParseStory_EmptyPagesUsesSafeFallbackNotRawJSON(t *testing.T) {
	// Valid JSON but no usable pages → must not return empty, and must NOT echo
	// the raw JSON back as story text.
	text := `{"title": "x", "pages": []}`
	story := parseStory(text, sampleReq)
	if len(story.Pages) == 0 {
		t.Fatal("empty pages must fall back to a safe story")
	}
	if strings.Contains(story.Pages[0].Text, "{") || strings.Contains(story.Pages[0].Text, "pages") {
		t.Fatalf("raw JSON leaked into story text: %q", story.Pages[0].Text)
	}
}

func TestParseStory_EmptyModelOutputStillNonEmpty(t *testing.T) {
	for _, text := range []string{"", "   ", "\n\n  \n"} {
		story := parseStory(text, sampleReq)
		if len(story.Pages) == 0 || strings.TrimSpace(story.Pages[0].Text) == "" {
			t.Fatalf("empty model output %q produced an empty story: %+v", text, story)
		}
	}
}

func TestParseStory_UnsafeContentReplacedWithSafeStory(t *testing.T) {
	text := `{"title":"밤","pages":[{"text":"괴물이 아이를 죽여버렸어요."}]}`
	story := parseStory(text, sampleReq)
	for _, p := range story.Pages {
		if containsUnsafe(p.Text) {
			t.Fatalf("unsafe text reached the reader: %q", p.Text)
		}
	}
	if story.Pages[0].Text != fallbackText {
		t.Fatalf("expected safe fallback, got %q", story.Pages[0].Text)
	}
}

func TestParseStory_SanitizesControlCharsAndCapsLength(t *testing.T) {
	long := strings.Repeat("\uac00", maxPageRunes+50)
	// JSON-escaped tab in the first page, an over-long second page.
	text := `{"title":"t","pages":[{"text":"\uc548\ub155\\t\ud558\uc138\uc694"}, {"text":"` + long + `"}]}`
	story := parseStory(text, sampleReq)
	if len(story.Pages) != 2 {
		t.Fatalf("expected 2 pages, got %d", len(story.Pages))
	}
	if strings.ContainsAny(story.Pages[0].Text, "\n\r\t") {
		t.Fatalf("control chars not neutralized: %q", story.Pages[0].Text)
	}
	if r := []rune(story.Pages[1].Text); len(r) > maxPageRunes {
		t.Fatalf("page length not capped: %d runes", len(r))
	}
}

func TestNewStoryID_UniquePerGeneration(t *testing.T) {
	// Each generation is a distinct artifact; ids must not collide even for the
	// same request (avoids overwriting saved stories).
	seen := map[string]bool{}
	for range 100 {
		id := newStoryID()
		if id == "" {
			t.Fatal("id must be non-empty")
		}
		if seen[id] {
			t.Fatalf("duplicate id: %s", id)
		}
		seen[id] = true
	}
}
