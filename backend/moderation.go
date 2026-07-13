package main

import (
	"strings"
	"unicode"
)

// moderationCategories is a curated, phrase-level child-safety lexicon applied to
// model output before it reaches a child. Terms are SEVERE and chosen to be
// low-false-positive on warm Korean bedtime content: bare ambiguous words are
// deliberately avoided (e.g. "죽" alone is 죽/porridge; "칼로" alone is cutting an
// apple; "피가" alone is a nosebleed) in favor of violent/graphic phrases.
//
// Terms are matched against text normalized by [normalizeForModeration], which
// collapses runs of whitespace to a SINGLE space (rather than removing it) so a
// term can't spuriously form across a word boundary — "엄마 약속" must not match
// "마약", "의자 살짝" must not match "자살". Multi-word terms therefore carry the
// single space that natural Korean text has between words.
//
// This deterministic pass is FAIL-SAFE: any hit replaces the whole story with the
// gentle default (see finalize). It is a real moderation layer, not the old
// stopgap denylist — but a model-based classification pass is still a worthwhile
// future addition for nuance the lexicon can't capture (see prompts/README).
var moderationCategories = []struct {
	name  string
	terms []string
}{
	{"death-violence", []string{
		"죽여", "죽였", "죽이고", "죽이는", "죽음", "살해", "살인",
		"목을 졸라", "목 졸라", "칼로 찌", "칼로 찔", "칼에 찌", "칼에 찔", "칼로 베",
		"총으로 쏘", "총을 쏘", "폭탄이 터", "murder",
	}},
	{"self-harm", []string{"자살", "스스로 목숨", "suicide"}},
	{"blood-gore", []string{"피투성이", "피범벅", "유혈"}},
	{"sexual", []string{"성관계", "성행위", "포르노", "야동", "자위행위", "자위 행위", "porn"}},
	{"drugs", []string{"마약", "필로폰", "코카인", "히로뽕", "cocaine", "heroin"}},
	{"abduction", []string{"납치", "유괴", "kidnap"}},
}

// isZeroWidth reports runes that carry no glyph and so could split a term
// invisibly: U+200B ZWSP, U+200C ZWNJ, U+200D ZWJ, U+FEFF BOM.
func isZeroWidth(r rune) bool {
	switch r {
	case 0x200B, 0x200C, 0x200D, 0xFEFF:
		return true
	default:
		return false
	}
}

// normalizeForModeration lowercases, drops zero-width characters (which could
// split a term invisibly), and collapses every run of whitespace/control to a
// single space. Collapsing to a single space (not removing it) preserves word
// boundaries so benign phrases like "엄마 약속" don't fabricate "마약".
func normalizeForModeration(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	prevSpace := false
	for _, r := range strings.ToLower(s) {
		switch {
		case isZeroWidth(r):
			// drop — invisible; would split a term
		case unicode.IsSpace(r), unicode.IsControl(r):
			if !prevSpace {
				b.WriteByte(' ')
				prevSpace = true
			}
		default:
			b.WriteRune(r)
			prevSpace = false
		}
	}
	return strings.TrimSpace(b.String())
}

// moderateText returns the first child-safety category a text trips, or "" if it
// is clean. Callers treat a non-empty result as fail-safe (replace with the safe
// default) and may log the category for tuning.
func moderateText(s string) string {
	norm := normalizeForModeration(s)
	if norm == "" {
		return ""
	}
	for _, cat := range moderationCategories {
		for _, term := range cat.terms {
			if strings.Contains(norm, term) {
				return cat.name
			}
		}
	}
	return ""
}
