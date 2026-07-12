package main

import (
	_ "embed"
	"fmt"
	"strings"
	"unicode"
)

// storyAuthorSystem is the canonical, versioned system prompt (persona, safety,
// style, output contract). It lives in the backend — NOT only in a Kagi profile
// — so the AI provider stays swappable and the prompt is version-controlled and
// testable (ADR 0001; codex plan review C1). The same file also seeds the Kagi
// "custom assistant" profile, so there is a single source of truth.
//
//go:embed prompts/story_author_system.md
var storyAuthorSystem string

// maxFieldRunes bounds short user-controlled prompt fields — names, interests
// (in runes, so multibyte Korean text isn't split mid-character).
const maxFieldRunes = 40

// maxTopicRunes bounds the free-text story seed (오늘의 이야기). It's a sentence,
// not a label, so it gets a larger cap than the short fields.
const maxTopicRunes = 120

// Count caps on user-derived lists so a crafted request can't flood the prompt
// (codex plan review C4). The app caps lower; the server is the real guard.
const (
	maxInterests  = 8
	maxSituations = 6
)

// sanitizeCapped reduces the prompt-injection surface of user-controlled fields:
// it strips control characters and newlines (so a value can't break out of its
// line and inject instructions) and caps length to max runes. This is a
// mitigation, not a substitute for the deferred output-moderation pass (README).
func sanitizeCapped(s string, max int) string {
	s = strings.Map(func(r rune) rune {
		if r == '\n' || r == '\r' || r == '\t' || unicode.IsControl(r) {
			return ' '
		}
		return r
	}, s)
	s = strings.TrimSpace(s)
	if r := []rune(s); len(r) > max {
		s = strings.TrimSpace(string(r[:max]))
	}
	return s
}

// sanitize is the short-field cap (names, interests, situation labels).
func sanitize(s string) string { return sanitizeCapped(s, maxFieldRunes) }

// sanitizeTopic is the free-text story-seed cap — same isolation, longer bound.
func sanitizeTopic(s string) string { return sanitizeCapped(s, maxTopicRunes) }

// maxCharacters caps how many extra characters a story can feature — enforced
// server-side so a crafted request can't stuff the prompt (planning/40, C1).
const maxCharacters = 5

// characterKindLabel maps a whitelisted kind to its Korean label. An unknown
// kind returns ok=false so the raw value never reaches the prompt.
func characterKindLabel(kind string) (string, bool) {
	switch kind {
	case "family":
		return "가족", true
	case "friend":
		return "친구", true
	case "animal":
		return "동물", true
	case "imaginary":
		return "상상 친구", true
	default:
		return "", false
	}
}

// characterLines sanitizes, caps, and labels the requested characters. Names are
// run through sanitize (same prompt-injection mitigation as other fields); an
// unknown kind is dropped rather than echoed.
func characterLines(chars []Character) []string {
	out := make([]string, 0, len(chars))
	for _, c := range chars {
		if len(out) >= maxCharacters {
			break
		}
		name := sanitize(c.Name)
		if name == "" {
			continue
		}
		if label, ok := characterKindLabel(c.Kind); ok {
			out = append(out, fmt.Sprintf("%s(%s)", name, label))
		} else {
			out = append(out, name)
		}
	}
	return out
}

// moodLabel maps a whitelisted mood to its Korean label. The tone each label
// implies is defined once in the system prompt (# 분위기), so the per-request
// prompt only names the selection. Unknown/empty → the cozy bedtime default.
func moodLabel(mood string) string {
	switch mood {
	case "cheerful":
		return "신나는"
	case "adventurous":
		return "모험적인"
	case "calm":
		return "잔잔한"
	case "playful":
		return "유쾌한"
	default: // "cozy" and anything unknown
		return "포근한"
	}
}

// ageBandLabel maps an age band to its Korean label; the system prompt
// (# 나이대별 표현) defines what each implies, so the per-request prompt only
// names the band.
func ageBandLabel(ageBand string) string {
	switch ageBand {
	case "infant":
		return "0~1세"
	case "toddler":
		return "2~3세"
	case "preschool":
		return "4~5세"
	case "kindergarten":
		return "6세"
	default:
		return "2~3세"
	}
}

// settingLabel maps a whitelisted backdrop to its Korean label. Unknown/empty
// returns ok=false so the AI picks a backdrop itself (planning/40).
func settingLabel(setting string) (string, bool) {
	switch setting {
	case "home":
		return "집", true
	case "forest":
		return "숲속", true
	case "sea":
		return "바닷속", true
	case "space":
		return "우주", true
	case "town":
		return "마을", true
	default:
		return "", false
	}
}

// lengthPages turns a requested length into a target page count. Bedtime stories
// benefit from real length, so these are generous (short ≈ what a whole short
// story should feel like). An empty/unknown length PRESERVES the age-band default
// so a caller that omits it keeps an age-appropriate length (planning/40, C2).
func lengthPages(length string, ageDefault int) int {
	switch length {
	case "short":
		return 8
	case "medium":
		return 13
	case "long":
		return 18
	default:
		return ageDefault
	}
}

// ageDefaultPages is the natural page count when no explicit length is chosen.
// Vocabulary/sentence guidance per age lives in the system prompt (# 나이대별
// 표현); this only sizes the story.
func ageDefaultPages(ageBand string) int {
	switch ageBand {
	case "infant": // 0-1
		return 5
	case "toddler": // 2-3
		return 7
	case "preschool": // 4-5
		return 9
	case "kindergarten": // 6
		return 11
	default:
		return 7
	}
}

// buildStoryMaterials assembles ONLY the per-request user turn: the child's
// materials + today's settings. The durable system prompt (persona/safety/style/
// age+mood definitions/output contract) is delivered separately — as a Kagi
// profile's instructions in profile mode, or prepended by buildStoryPrompt for
// the base-model path — so it isn't re-sent in every request.
func buildStoryMaterials(req StoryRequest) string {
	labels := situationLabels()
	situations := make([]string, 0, len(req.SituationIDs))
	for _, id := range req.SituationIDs {
		if len(situations) >= maxSituations {
			break
		}
		// Only known ids map to trusted labels; unknown ids are sanitized so a
		// crafted id can't inject prompt instructions.
		if label, ok := labels[id]; ok {
			situations = append(situations, label)
		} else if s := sanitize(id); s != "" {
			situations = append(situations, s)
		}
	}

	name := sanitize(req.ChildName)
	if name == "" {
		name = "우리 아이"
	}
	interests := make([]string, 0, len(req.Interests))
	for _, in := range req.Interests {
		if len(interests) >= maxInterests {
			break
		}
		if s := sanitize(in); s != "" {
			interests = append(interests, s)
		}
	}
	companion := sanitize(req.CompanionName)
	characters := characterLines(req.Characters)
	pages := lengthPages(req.Length, ageDefaultPages(req.AgeBand))

	// Only per-request values — never duplicated instruction sentences (those live
	// once in the system prompt). [이야기 재료] is user-derived (untrusted,
	// quarantined by the system prompt); [오늘의 설정] is backend-derived selections
	// (trusted labels the system prompt defines).
	topic := sanitizeTopic(req.Topic)

	var b strings.Builder
	b.WriteString("[이야기 재료]\n")
	b.WriteString(fmt.Sprintf("- 주인공 아이: %s\n", name))
	if topic != "" {
		b.WriteString(fmt.Sprintf("- 오늘의 이야기: %s\n", topic))
	}
	if len(interests) > 0 {
		b.WriteString(fmt.Sprintf("- 좋아하는 것: %s\n", strings.Join(interests, ", ")))
	}
	if companion != "" {
		b.WriteString(fmt.Sprintf("- 함께하는 친구: %s\n", companion))
	}
	if len(characters) > 0 {
		b.WriteString(fmt.Sprintf("- 등장인물: %s\n", strings.Join(characters, ", ")))
	}
	if len(situations) > 0 {
		b.WriteString(fmt.Sprintf("- 오늘의 상황/주제: %s\n", strings.Join(situations, ", ")))
	}
	if label, ok := settingLabel(req.Setting); ok {
		b.WriteString(fmt.Sprintf("- 이야기의 배경: %s\n", label))
	}
	b.WriteString("\n[오늘의 설정]\n")
	b.WriteString(fmt.Sprintf("- 나이대: %s\n", ageBandLabel(req.AgeBand)))
	b.WriteString(fmt.Sprintf("- 분위기: %s\n", moodLabel(req.Mood)))
	b.WriteString(fmt.Sprintf("- 목표 페이지 수: 정확히 %d개\n", pages))
	return b.String()
}

// buildStoryPrompt is the self-contained prompt (system prompt + materials) used
// on the base-model path — when no Kagi profile carries the system prompt — and
// in tests. In profile mode the handler sends only buildStoryMaterials, since the
// profile's instructions (created from the same embedded .md) ARE the system
// prompt, so it isn't re-sent per request.
func buildStoryPrompt(req StoryRequest) string {
	return storyAuthorSystem + "\n\n" + buildStoryMaterials(req)
}
