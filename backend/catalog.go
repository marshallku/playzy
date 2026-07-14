package main

// situation mirrors the app's default catalog so the SDUI document served here
// matches the bundled offline fallback (single source of ids/labels).
type situation struct {
	ID    string
	Label string
	Kind  string // "parenting" | "value" | "theme"
	Emoji string
}

// catalogSituations MUST mirror the app's kDefaultSituations (single source of
// ids/labels/kinds; app/lib/domain/situation.dart). Three kinds: parenting (the
// wedge), value (담고 싶은 마음/가치 — routed to its own prompt line), theme.
var catalogSituations = []situation{
	{"bedtime", "잠자기", "parenting", "🌙"},
	{"teeth", "양치하기", "parenting", "🪥"},
	{"potty", "배변 훈련", "parenting", "🚽"},
	{"sharing", "나눠 쓰기", "parenting", "🤝"},
	{"daycare", "어린이집 가기", "parenting", "🎒"},
	{"dark", "어둠이 무서워요", "parenting", "💡"},
	{"sibling", "동생이 생겼어요", "parenting", "👶"},
	{"veggies", "골고루 먹기", "parenting", "🥕"},
	{"hospital", "병원 가기", "parenting", "🏥"},
	{"tantrum", "떼쓰지 않기", "parenting", "😤"},
	{"alone_sleep", "혼자 자기", "parenting", "🛏️"},
	{"tidy", "정리정돈", "parenting", "🧸"},
	{"challenge", "새로운 것 도전", "parenting", "🌟"},
	{"courage", "용기", "value", "💪"},
	{"generosity", "나눔", "value", "🤲"},
	{"honesty", "정직", "value", "😊"},
	{"caring", "배려", "value", "🫂"},
	{"patience", "인내", "value", "🌱"},
	{"gratitude", "감사", "value", "🙏"},
	{"confidence", "자신감", "value", "⭐"},
	{"animals", "동물 친구들", "theme", "🐰"},
	{"space", "우주 여행", "theme", "🚀"},
	{"ocean", "바닷속 모험", "theme", "🐚"},
	{"forest", "숲속 이야기", "theme", "🌳"},
	{"dino", "공룡 나라", "theme", "🦕"},
	{"magic", "마법 세계", "theme", "✨"},
	{"snow", "눈 나라", "theme", "❄️"},
	{"amusement", "놀이공원", "theme", "🎡"},
	{"vehicles", "신나는 탈것", "theme", "🚗"},
}

// situationLabels maps ids → Korean labels for the prompt builder.
func situationLabels() map[string]string {
	m := make(map[string]string, len(catalogSituations))
	for _, s := range catalogSituations {
		m[s.ID] = s.Label
	}
	return m
}

// situationKinds maps ids → kind so the prompt builder can route value picks
// (담고 싶은 마음) to their own line, separate from 상황/주제.
func situationKinds() map[string]string {
	m := make(map[string]string, len(catalogSituations))
	for _, s := range catalogSituations {
		m[s.ID] = s.Kind
	}
	return m
}

// situationCatalogSDUI builds the SDUI document the app renders (ADR 0003),
// matching the app's bundled default: two sections + two chip groups.
func situationCatalogSDUI() map[string]any {
	chips := func(kind string) []map[string]any {
		out := []map[string]any{}
		for _, s := range catalogSituations {
			if s.Kind == kind {
				out = append(out, map[string]any{"id": s.ID, "label": s.Label, "emoji": s.Emoji})
			}
		}
		return out
	}
	return map[string]any{
		"schemaVersion": 1,
		"components": []map[string]any{
			{"type": "section", "title": "요즘 이런 상황이 있나요?"},
			{"type": "chip_group", "chips": chips("parenting")},
			{"type": "section", "title": "이야기에 담고 싶은 마음"},
			{"type": "chip_group", "chips": chips("value")},
			{"type": "section", "title": "어떤 모험을 떠날까요?"},
			{"type": "chip_group", "chips": chips("theme")},
		},
	}
}
