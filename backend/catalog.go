package main

// situation mirrors the app's default catalog so the SDUI document served here
// matches the bundled offline fallback (single source of ids/labels).
type situation struct {
	ID    string
	Label string
	Kind  string // "parenting" | "theme"
	Emoji string
}

var catalogSituations = []situation{
	{"bedtime", "잠자기", "parenting", "🌙"},
	{"teeth", "양치하기", "parenting", "🪥"},
	{"potty", "배변 훈련", "parenting", "🚽"},
	{"sharing", "나눠 쓰기", "parenting", "🤝"},
	{"daycare", "어린이집 가기", "parenting", "🎒"},
	{"dark", "어둠이 무서워요", "parenting", "💡"},
	{"sibling", "동생이 생겼어요", "parenting", "👶"},
	{"veggies", "골고루 먹기", "parenting", "🥕"},
	{"animals", "동물 친구들", "theme", "🐰"},
	{"space", "우주 여행", "theme", "🚀"},
	{"ocean", "바닷속 모험", "theme", "🐚"},
	{"forest", "숲속 이야기", "theme", "🌳"},
	{"dino", "공룡 나라", "theme", "🦕"},
	{"magic", "마법 세계", "theme", "✨"},
}

// situationLabels maps ids → Korean labels for the prompt builder.
func situationLabels() map[string]string {
	m := make(map[string]string, len(catalogSituations))
	for _, s := range catalogSituations {
		m[s.ID] = s.Label
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
			{"type": "section", "title": "어떤 모험을 떠날까요?"},
			{"type": "chip_group", "chips": chips("theme")},
		},
	}
}
