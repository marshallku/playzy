# MVP scope — iOS launch

> Evidence: `research/ai-story-generator-competitor-analysis.md`,
> `research/design.md`. Positioning: the market gap is a **0–6 dedicated,
> parenting-situation-solving** story generator — most competitors target 3–12
> broadly, and Korea's install leader (스토리셀프) is *personalization*, not
> *generation*. That gap is our wedge.

## In scope (v1)

### 1. Onboarding
- Warm, 2–3 screen intro. Minimal friction. No account required to *try*
  (anonymous device account); sign-in offered before/at paywall.

### 2. Child profile (native, local-first)
Set up once, remembered. Fields (kept small — bedtime, one-handed):
- Name (used in the story)
- Age / age band (0–1, 2–3, 4–5, 6) — drives vocabulary, length, tone
- A few interests / favorite things (animals, vehicles, colors…) — chips
- Optional: pronoun/gender, a sibling or companion name

Multiple children supported (switcher), but one is enough for v1.

### 3. Situation picker (SDUI — ADR 0003)
The core differentiator. Parent taps a few **situations/themes** for tonight.
Catalog served by backend so it grows without an app release. Two families:

- **Parenting situations (the wedge):** going to sleep / bedtime refusal,
  brushing teeth, potty training, sharing, separation anxiety (daycare),
  fear of the dark, new sibling, eating veggies, doctor visit.
- **Adventure/theme:** animals, space, ocean, forest, dinosaurs, magic,
  seasons, grandma's house.

Multi-select, small number (1–3) encouraged. Optional story length & tone.

### 4. Story generation
- App → Playzy backend (`StoryApi`) → provider (`KagiProvider` now) — ADR 0001.
- A delightful "story is being written" loading moment (Lottie/Rive).
- **Text-only for MVP** (D3). Structured output: title + pages (so the reader
  can paginate). Age-appropriate guardrails enforced in the prompt.

### 5. Story reader (native, offline-capable)
- Bedtime-first: night mode, font-size slider (18–28pt), brightness, auto-fading
  chrome, gentle page-turn. Single column.
- Save / library of generated stories (local; sync later).

### 6. Free-tier gating + paywall
- **3 free stories lifetime** (D2 — matches market standard), then paywall.
- Enforced **server-side** by entitlement/quota (un-bypassable) — ADR 0002.
- Paywall presentation may be a WebView experiment surface; the transaction is
  **Apple IAP via RevenueCat** on iOS (ADR 0002). Real payment gated on D1
  confirmation; until then a `FakePaymentGateway` grants entitlements for dev.

## Out of scope (v1 — fast-follows)

- AI illustrations per story (D3) — text-only first.
- Audio narration / TTS, **parent voice cloning** (strong differentiator, later).
- Character consistency across stories, physical print.
- Social sharing / community.
- Android & web store launch (web exists only as experiment host).
- Multi-language beyond Korean + English content.

## Table-stakes we knowingly defer

Competitor research shows text+illustration+**audio narration** is now table
stakes. We launch text-only to ship the *wedge* (0–6 situation-solving) fast,
with illustration + narration as the first paid-tier fast-follow. This is a
deliberate, documented trade-off, not an oversight.

## Success signal for v1

A tired parent can, in under a minute from opening the app, produce a warm,
personalized, age-appropriate bedtime story addressing tonight's real situation
(e.g. "won't brush teeth") and read it in a dark room comfortably.
