# 50 — Story-creation funnel redesign

Feedback after the story-richness work (planning/40): the creation flow felt
awkward and the inputs didn't match how a parent actually thinks about tonight's
story. This plan reworks the flow. Decisions below were confirmed with the
product owner.

## Problems (product owner)

1. The story used the child's **full name incl. surname**. A bedtime tale should
   address the child by given name only.
2. Picking "요즘 상황" from a **fixed chip grid every time** is awkward — there was
   no way to just say what tonight is about.
3. Picking a **place/adventure** ("어떤 모험을 떠날까요?") felt forced.
4. There was **no way to reuse characters** — they had to be retyped each story.

Meta: fixing 2 & 3 risks a more complex funnel, so it must show **progress** to
reduce drop-off.

## Decisions

- **Name (성/이름):** `ChildProfile.name` → `givenName` (required, the ONLY name
  used in the story) + `familyName` (optional, collected but never used in the
  story). Legacy single `name` migrates to `givenName` **verbatim** (auto-split
  is unreliable — "하준" is a given name, not 하+준; pre-launch has no real legacy
  PII, and the two-field editor lets the parent correct it).
- **Subject:** keep the situation/theme **chips AND add a free-text seed**
  (오늘의 이야기). Either one is enough; both enrich. The seed rides the wire as
  `topic` (sanitized, ≤120 runes, untrusted). Backend requires `topic` **OR** ≥1
  `situationId`.
- **Place:** the `setting`/place picker is **removed** (#3) — from the app UI and,
  in the follow-up cleanup, from the `StoryRequest` wire (Go + Dart) entirely. The
  theme chips (우주/바다/공룡…) remain as subject tags.
- **Characters:** a reusable **roster (보관함)** — saved once, picked per story.
  The profile's legacy single `companionName` is **migrated into the roster once**
  (seed-on-first-read, idempotent). A story features at most 5 of them.
- **Funnel:** **3 separate routes** — `/create/topic` → `/create/cast` →
  `/create/tone` — each with a **progress bar** ("n / 3"). State lives in a shared
  `storyDraftProvider`, so native iOS back-swipe between steps preserves choices;
  an X exits to Home in one tap. The draft is reset at exactly **one** point (the
  Home CTA / fresh entry), never mid-funnel, so a failed generation keeps choices.

## Work units (each: plan → implement → unit test → e2e/build → cross-review → save)

1. **WU1 — topic on the wire + prompt.** `StoryRequest.topic` (Go + Dart),
   `buildStoryMaterials` seed line, validate topic OR situation, fake reflects it.
2. **WU2 — name split.** `givenName`/`familyName`, verbatim legacy migration,
   two-field editor, given-name-only story request.
3. **WU3 — character roster.** Repository (+ companion migration seam), controller,
   `RosterScreen`, Home entry.
4. **WU4 — the 3-step funnel.** Shared draft + progress scaffold, topic/cast/tone
   screens, cast cap 5, place removed, old picker/options screens deleted.
5. **WU5 — verification + docs.** Tests, real-backend e2e of the new request shape,
   this doc + verification update.

## Plan review (codex, 2026-07-13)

- **Name privacy (C1):** verbatim legacy migration + two-field editor (no forced
  review screen — protect the one-minute wedge; no real legacy PII pre-launch).
- **Companion migration ordering (C2):** keep `companionName` in the profile JSON
  (deprecated, out of UI) so the roster seed can always read it; seed-once is
  keyed on the roster key's presence and persisted even when empty.
- **Validate after normalizing (C3):** sanitize the topic before the topic-OR-
  situation check, so whitespace/control-only can't pass and consume quota.
- **Cap coupling (C4):** the roster stores ≤12; a single story selects ≤5, enforced
  in the cast UI (unselected chips disabled at the cap).
- **Draft reset (C5/I6/I7):** single reset at fresh entry (Home); cancel = go(home);
  the tone step keeps the profile/quota resolving + retry guard; never reset before
  generation so a failed run keeps the choices.

## Supersedes

Reverses planning/40's `setting` (장소) knob and replaces its situation-picker →
story-options flow. The characters/mood/length controls from 40 carry forward.
