package main

import (
	"fmt"
	"strings"
	"unicode"
)

// maxFieldRunes bounds user-controlled prompt fields (in runes, so multibyte
// Korean text isn't split mid-character).
const maxFieldRunes = 40

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
		// Only known ids map to trusted labels; unknown ids are sanitized so a
		// crafted id can't inject prompt instructions.
		if label, ok := labels[id]; ok {
			situations = append(situations, label)
		} else {
			situations = append(situations, sanitize(id))
		}
	}

	name := sanitize(req.ChildName)
	if name == "" {
		name = "우리 아이"
	}
	interests := make([]string, 0, len(req.Interests))
	for _, in := range req.Interests {
		if s := sanitize(in); s != "" {
			interests = append(interests, s)
		}
	}
	companion := sanitize(req.CompanionName)
	guidance, pages := ageGuidance(req.AgeBand)

	var b strings.Builder
	b.WriteString("당신은 영유아(0~6세)를 위한 따뜻한 동화 작가입니다.\n")
	b.WriteString(fmt.Sprintf("주인공 아이의 이름은 '%s'입니다.\n", name))
	if len(interests) > 0 {
		b.WriteString(fmt.Sprintf("아이가 좋아하는 것: %s.\n", strings.Join(interests, ", ")))
	}
	if companion != "" {
		b.WriteString(fmt.Sprintf("이야기에 '%s'도 함께 등장시켜 주세요.\n", companion))
	}
	if len(situations) > 0 {
		b.WriteString(fmt.Sprintf("오늘 다룰 상황/주제: %s.\n", strings.Join(situations, ", ")))
	}
	b.WriteString(fmt.Sprintf("나이에 맞는 표현: %s\n", guidance))
	b.WriteString("\n안전 규칙(반드시 지킬 것):\n")
	b.WriteString("- 폭력, 공포, 차별, 성인 주제를 절대 넣지 마세요.\n")
	b.WriteString("- 다치거나 무섭게 하지 말고, 안심되고 긍정적으로 끝나게 하세요.\n")
	b.WriteString("- 잠들기 전에 읽어주기 좋은 포근한 결말로 마무리하세요.\n")
	b.WriteString(fmt.Sprintf("\n%d개 내외의 짧은 페이지로 나눠 주세요.\n", pages))
	b.WriteString("\n반드시 아래 형식의 JSON만 출력하세요. 다른 설명이나 코드펜스는 넣지 마세요:\n")
	b.WriteString(`{"title": "제목", "pages": [{"text": "첫 페이지"}, {"text": "다음 페이지"}]}`)
	return b.String()
}
