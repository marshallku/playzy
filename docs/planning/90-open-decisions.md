# Open decisions

Decisions that need the user (or evidence) before they're locked. Each is built
to be **swappable** so work isn't blocked. Referenced from ADRs by ID.

| ID | Decision | Default we're building toward | Blocks | Status |
| --- | --- | --- | --- | --- |
| D1 | iOS monetization model & price | Apple IAP (RevenueCat); **both** a monthly subscription + one-time credit pack; price TBD | Phase 5 real payment | Open — confirm before wiring live IAP |
| D2 | Free-tier limit (how many free stories) | Provisional: **3 free stories**, then paywall | Backend quota + paywall copy | Open — refine with competitor benchmarks |
| D3 | In-story illustration strategy | **Text-only MVP**; art is a fast-follow | Story reader, cost model | Open — see design ⚠️ flags |
| D4 | Brand primary hue | Periwinkle `#4E6FBC` (AA-compliant; research's `#6A89CC` failed AA) | Final DESIGN.md tokens | Open — needs designer; must keep ≥4.5:1 with onBrand text |
| D5 | Backend hosting for launch | kagi is dev-only; real host TBD | Production launch | Open — not needed for MVP dev |
| D6 | Streaming vs unary story delivery | Unary first, SSE-ready | Story reader UX | Low-stakes; deferred |
| D7 | Read-aloud / TTS | Deferred to post-MVP | Reader features | Deferred |
| D8 | Gmarket Sans display font | Bundle Pretendard (OFL) now; display falls back to Pretendard until Gmarket Sans license is cleared | Display/brand type 1:1 | Open — license review |

## How defaults are chosen

Per the decision framework: pick the option that is cheapest to reverse, keep it
behind an interface, and note it here. None of these block building the design
system or the app shell.

## Things flagged as "needs a professional designer / tool"

(From design research — see `research/design.md` and `DESIGN.md` §Deferred.)

1. Mascot / brand character (commission an illustrator).
2. In-story illustration style bible (+ D3).
3. Full 50–900 tonal color ramps + final brand hue (D4).
4. Custom icon set beyond SF Symbols.
5. App icon + onboarding hero art.

These are isolated behind design tokens + asset slots so a designer's output
drops in without code changes.
