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

// maxFieldRunes bounds user-controlled prompt fields (in runes, so multibyte
// Korean text isn't split mid-character).
const maxFieldRunes = 40

// Count caps on user-derived lists so a crafted request can't flood the prompt
// (codex plan review C4). The app caps lower; the server is the real guard.
const (
	maxInterests  = 8
	maxSituations = 6
)

// sanitize reduces the prompt-injection surface of user-controlled fields: it
// strips control characters and newlines (so a value can't break out of its
// line and inject instructions) and caps length. This is a mitigation, not a
// substitute for the deferred output-moderation pass (see README).
func sanitize(s string) string {
	s = strings.Map(func(r rune) rune {
		if r == '\n' || r == '\r' || r == '\t' || unicode.IsControl(r) {
			return ' '
		}
		return r
	}, s)
	s = strings.TrimSpace(s)
	if r := []rune(s); len(r) > maxFieldRunes {
		s = strings.TrimSpace(string(r[:maxFieldRunes]))
	}
	return s
}

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

// moodGuidance turns a whitelisted mood into a tone instruction. Unknown/empty
// defaults to the cozy bedtime tone.
func moodGuidance(mood string) string {
	switch mood {
	case "cheerful":
		return "밝고 신나는 분위기로, 즐거운 에너지가 느껴지게."
	case "adventurous":
		return "설레는 모험의 분위기로, 용기와 발견이 담기게."
	case "calm":
		return "잔잔하고 차분한 분위기로, 마음이 편안해지게."
	case "playful":
		return "유쾌하고 장난스러운 분위기로, 웃음이 나게."
	default: // "cozy" and anything unknown
		return "포근하고 안심되는 분위기로, 사랑받는 느낌이 들게."
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

// lengthPages turns a requested length into a target page count. An empty/unknown
// length PRESERVES the age-band default so older clients that omit it keep their
// age-appropriate length (planning/40, C2 — backward compatible).
func lengthPages(length string, ageDefault int) int {
	switch length {
	case "short":
		return 3
	case "medium":
		return 5
	case "long":
		return 7
	default:
		return ageDefault
	}
}

// ageGuidance tunes vocabulary, length, and tone per age band (docs/planning/10).
func ageGuidance(ageBand string) (guidance string, pages int) {
	switch ageBand {
	case "infant": // 0-1
		return "아주 짧고 단순한 문장, 반복되는 리듬, 의성어/의태어 위주.", 3
	case "toddler": // 2-3
		return "짧고 쉬운 문장, 익숙한 일상 소재, 따뜻하고 안심되는 톤.", 4
	case "preschool": // 4-5
		return "간단한 기승전결, 공감과 작은 교훈, 호기심을 자극하는 전개.", 5
	case "kindergarten": // 6
		return "조금 더 풍부한 어휘와 이야기 구조, 용기·배려 같은 가치를 자연스럽게.", 6
	default:
		return "짧고 쉬운 문장, 따뜻하고 안심되는 톤.", 4
	}
}

// buildStoryPrompt assembles the Korean prompt sent to the AI. It bakes in
// safety guardrails and asks for STRICT JSON so the response parses reliably.
func buildStoryPrompt(req StoryRequest) string {
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
	guidance, ageDefaultPages := ageGuidance(req.AgeBand)
	pages := lengthPages(req.Length, ageDefaultPages)

	// The canonical system prompt (persona/safety/style/output contract) is the
	// embedded .md; the backend appends only the per-request materials + trusted
	// writing directives. [이야기 재료] is user-derived (untrusted, quarantined by
	// the system prompt); [집필 지침] is backend-derived (whitelisted → trusted).
	var b strings.Builder
	b.WriteString(storyAuthorSystem)
	b.WriteString("\n\n[이야기 재료]\n")
	b.WriteString(fmt.Sprintf("- 주인공 아이: %s\n", name))
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
	b.WriteString("\n[집필 지침]\n")
	b.WriteString(fmt.Sprintf("- 분위기: %s\n", moodGuidance(req.Mood)))
	b.WriteString(fmt.Sprintf("- 나이에 맞는 표현: %s\n", guidance))
	b.WriteString(fmt.Sprintf("- 목표 페이지 수: 정확히 %d개\n", pages))
	b.WriteString("\n이제 위 재료로 아이를 위한 취침 동화를 지어 주세요.")
	return b.String()
}
