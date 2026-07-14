# 60 — Story inputs: a 가치(교훈) axis + a richer catalog

Feedback from the product owner: the creation options felt **thin** — not obviously
worth using 3+ times — while the worry was that *more freedom* could either raise
the bar for a tired parent or let people make non-stories. This plan threads that
needle: add **curated** replay variety without opening a freedom vector.

## Why this, grounded in research

`docs/research/ai-story-generator-competitor-analysis.md` §4 (input-parameter
union) shows the industry-standard 0–6 set: 이름 → 나이 → 관심사 → 테마 →
**교훈/가치** → (음성). Playzy had every axis **except 가치/교훈** — a table-stakes
gap present in Snugglish (7 values), Oscar (5), Bedtimestory. The design reference
(`Playzy.dc.html`) independently shows the same axis in funnel step 1 ("이야기에
담고 싶은 마음"). Separately, 우리이야기's 20+ 육아상황 is the KR differentiator; we
had 8.

Curated chips are **on-rails**: the only freedom vector is the free-text seed
(`topic`), which is already capped (≤120 runes), control-char-stripped, and
quarantined by the system prompt. So adding chips multiplies replay combinations
(테마 × 가치 × 상황) **without** adding derail risk.

## Decisions

- **New `value` kind (가치/마음).** Curated 7: 용기·나눔·정직·배려·인내·감사·자신감.
  A third funnel section, "이야기에 담고 싶은 마음". Selected ids ride the **same**
  `situationIds` set as subjects (one selection model, no new wire field).
- **Backend routes by kind.** `buildStoryMaterials` splits selected ids: `value`
  ids → a distinct **`- 담고 싶은 마음:`** prompt line; parenting/theme/unknown →
  `- 오늘의 상황/주제:`. Both share one `maxSituations` budget (no per-line flood).
- **System prompt** gains a 담고 싶은 마음(가치) material bullet with an explicit
  **embody-don't-preach** instruction (reinforcing the existing 훈계 금지 rule).
- **Catalog expansion** (curated, tasteful): parenting 8→13 (+병원·떼쓰기·혼자
  자기·정리정돈·새로운 것 도전), theme 6→9 (+눈 나라·놀이공원·탈것).
- **Pick cap 3→4** (`maxSituationsPerStory`) so a value can ride on top of a
  subject without crowding it out. Server cap (`maxSituations`=6) is the real
  guard; unselected chips disable at the cap (unchanged UI logic).
- **No "surprise/random" button** — considered, dropped: it needs a randomness
  contract (test flakiness) and, with SDUI chips carrying no kind client-side,
  couldn't reliably pick a themed seed. Revisit if replay data warrants it.

## Single source of truth

`app/lib/domain/situation.dart` `kDefaultSituations` and `backend/catalog.go`
`catalogSituations` must stay mirrored (ids/labels/kinds). The bundled SDUI and
the server SDUI both render three sections.

## What did NOT change

The wire (`StoryRequest.situationIds`) is unchanged — values are just more ids.
No migration. `topic` free-text and the safety/isolation model are untouched.
