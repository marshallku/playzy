package main

import "testing"

func TestModerateText_BlocksEachCategory(t *testing.T) {
	cases := map[string]string{
		"괴물이 아이를 죽여버렸어요":   "death-violence",
		"그는 스스로 목숨을 끊었어요":  "self-harm",
		"바닥이 피투성이가 되었어요":   "blood-gore",
		"둘은 성관계를 했어요":      "sexual",
		"그들은 마약을 팔았어요":     "drugs",
		"낯선 사람이 아이를 납치했어요": "abduction",
	}
	for text, wantCat := range cases {
		if got := moderateText(text); got != wantCat {
			t.Errorf("moderateText(%q) = %q, want %q", text, got, wantCat)
		}
	}
}

func TestModerateText_AllowsBenignBedtimeText(t *testing.T) {
	// These MUST pass — over-blocking shows the gentle default instead of a fine
	// story. They contain look-alikes of blocked terms in safe contexts.
	safe := []string{
		"포근한 밤이에요. 오늘도 참 잘했어요. 이제 편안히 잠들어요.",
		"하준이는 죽을 맛있게 다 먹었어요.",     // 죽(porridge), not 죽여/죽음
		"엄마가 칼로 사과를 예쁘게 잘라 주셨어요.", // 칼로(cutting fruit), not 칼로 찌르다
		"어제 코피가 조금 났지만 금세 멈췄어요.",  // 코피가, not a gore phrase
		"하나도 안 무서워요. 이불 속은 포근해요.", // 무섭 is intentionally NOT blocked
		"동생이 새로 생겨서 정말 기뻐요.",
		"엄마 약속했어요, 내일 또 놀아 준다고.", // 엄마 약속 must NOT fabricate 마약 (codex C1)
		"의자 살짝 밀고 자리에 앉았어요.",     // 의자 살짝 must NOT fabricate 자살 (codex C1)
	}
	for _, s := range safe {
		if got := moderateText(s); got != "" {
			t.Errorf("benign text wrongly blocked: %q → category %q", s, got)
		}
	}
}

func TestModerateText_ResistsZeroWidthEvasion(t *testing.T) {
	// Zero-width runes are built from code points so the source stays visible.
	zwsp := string(rune(0x200B)) // ZWSP
	zwnj := string(rune(0x200C)) // ZWNJ
	zwj := string(rune(0x200D))  // ZWJ
	bom := string(rune(0xFEFF))  // BOM

	// Invisible (zero-width) injections inside a term must not slip past the
	// matcher — they're dropped during normalization. (Ordinary spaces are NOT
	// collapsed away, to preserve word boundaries; that's covered by the benign
	// test above.)
	evasions := []string{
		"괴물이 아이를 죽" + zwsp + "여 버렸어요",        // ZWSP inside 죽여
		"그는 자" + zwj + "살을 생각했어요",            // ZWJ inside 자살
		"그는 " + bom + "마" + zwnj + "약을 팔았어요", // BOM + ZWNJ inside 마약
	}
	for _, s := range evasions {
		if moderateText(s) == "" {
			t.Errorf("zero-width evasion slipped through moderation: %q", s)
		}
	}
}

func TestModerateText_EmptyIsClean(t *testing.T) {
	if got := moderateText("   \n\t "); got != "" {
		t.Errorf("whitespace-only should be clean, got %q", got)
	}
}
