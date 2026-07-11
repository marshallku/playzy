# 40 — Richer stories & a real home

Feedback after M2: generated stories feel same-y (thin inputs, and dev runs on
fakes), and the home screen is bare (title + one button). This plan adds
generation-time story controls, richer prompting, story persistence, and a home
that feels like a home. Decisions below were confirmed with the product owner.

## Decisions

- **Characters (등장인물):** per-story list of `{name, kind}` where kind ∈
  가족/친구/동물/상상 친구. Distinct from the profile's single `companionName`
  (which stays as a default). Cap 5 per story.
- **Story knobs at generation time:** 분위기(mood), 길이(length), 장소(setting).
  (Not lesson/moral — deferred.)
- **Home content:** name greeting + "오늘의 동화" hero CTA, 지난 이야기 보관함
  (needs new story persistence), 이용권/무료 현황 card. (Not quick-situation
  shortcuts.)

## Schema (StoryRequest additions — app ⇄ backend wire, ADR 0001)

The app never builds a prompt; it sends a provider-agnostic request. New fields
are additive and optional so existing callers/tests keep working.

```jsonc
{
  // ...existing: childName, ageBand, situationIds, interests, companionName
  "characters": [{ "name": "하율", "kind": "family" }],   // ≤5, sanitized
  "mood":    "cozy",      // cozy|cheerful|adventurous|calm|playful (default cozy)
  "length":  "medium",    // short|medium|long (default medium)
  "setting": "forest"     // optional; home|forest|sea|space|town (omit = AI picks)
}
```

- `kind`: `family|friend|animal|imaginary` → 가족/친구/동물/상상 친구. Unknown kind
  → name kept, kind label dropped (never inject a raw kind string).
- `length` → pages: short 3 / medium 5 / long 7. Overrides the age-band page
  default; age band still drives vocabulary/tone.
- `mood`/`setting`: whitelist-mapped to Korean prompt phrasing. Unknown → default
  (mood) or omitted (setting). Never echo an unknown value into the prompt.

## Work units (each: plan → implement → unit test → e2e/build → cross-review → save)

1. **WU1 — model + prompt.** Domain enums + `StoryCharacter` (app), `StoryRequest`
   fields (app + Go), `buildStoryPrompt` uses characters/mood/length/setting,
   `FakeStoryApi` reflects mood + first character so the demo isn't flat. Go +
   Dart unit tests.
2. **WU2 — options UI.** After the situation picker, a story-options step:
   add/remove characters (name + kind dropdown), mood dropdown, length segmented,
   setting dropdown. Builds the enriched request. Widget + e2e.
3. **WU3 — library + home.** `StoryLibrary` persistence (shared_preferences JSON
   list), save on successful generation; home redesign (greeting + hero + recent
   stories + quota card). Widget + e2e.

## Safety

Characters are user-controlled → same treatment as other prompt fields: strip
control chars/newlines, cap length (reuse `sanitize`), cap count. Output-moderation
pass is still the deferred backstop (README).

## Revisions after plan review (codex, 2026-07-11)

- **Length backward-compat (C2):** omitted `length` **preserves the age-band page
  count**; only an explicit length overrides to 3/5/7. Age still drives vocab/tone.
- **Server-side character validation + isolation (C1):** the backend (not just the
  app) caps ≤5 characters, sanitizes each name, and whitelists `kind`. All
  user-controlled fields are framed in the prompt as *reference data, not
  instructions*. Add `http.MaxBytesReader` on the request body. Deep moderation
  stays deferred.
- **Identity/time (C4):** backend already stamps `createdAt` (`main.go:124`). The
  library orders by **insertion order** (most-recent first), not by parsing time,
  so the deterministic `FakeStoryApi` stays test-stable (I2) while chronology still
  works. Fake IDs incorporate mood/length/characters so varied inputs differ.
- **Persistence robustness (C5):** `StoryLibrary` decodes **per-entry** (skip
  corrupt/legacy entries, never fail the whole load), bounds retention (keep last
  30), and dedupes by story id (move-to-front).
- **Save transaction (C3):** persistence happens **after** a successful generation
  as **best-effort** — a save failure neither regenerates nor re-charges; the
  reader still shows the story. Distinct from generation failure.
- **Scope split (I3):** WU3 → **WU3a** (StoryLibrary persistence + save) and
  **WU3b** (home redesign) so the home consumes an already-built library.
- **Hero (I4):** the hero CTA is always the generation entry point (not
  today-specific); the library section is hidden when empty — no timezone logic.
