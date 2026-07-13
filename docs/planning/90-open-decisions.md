# Open decisions

Decisions that need the user (or evidence) before they're locked. Each is built
to be **swappable** so work isn't blocked. Referenced from ADRs by ID.

| ID | Decision | Default we're building toward | Blocks | Status |
| --- | --- | --- | --- | --- |
| D1 | iOS monetization model & price | **Resolved:** credit packs only (no subscription), Apple IAP consumable. Provisional: 10 stories / ₩4,900 | Phase 5 real payment | **Resolved 2026-07-11** — user chose credit-packs-only |
| D2 | Free-tier limit (how many free stories) | Provisional: **3 free stories**, then paywall | Backend quota + paywall copy | Open — refine with competitor benchmarks |
| D3 | In-story illustration strategy | **Text-only MVP**; art is a fast-follow | Story reader, cost model | Open — see design ⚠️ flags |
| D4 | Brand primary hue | Periwinkle `#5265C6` (AA-compliant ≈5.2:1 with white; from the design-system renewal) | Final DESIGN.md tokens | Open — needs designer; must keep ≥4.5:1 with onBrand text |
| D5 | Backend hosting for launch | kagi is dev-only; real host TBD | Production launch | Open — not needed for MVP dev |
| D6 | Streaming vs unary story delivery | Unary first, SSE-ready | Story reader UX | Low-stakes; deferred |
| D7 | Read-aloud / TTS | Deferred to post-MVP | Reader features | Deferred |
| D8 | Brand/display + story fonts | **Resolved:** Fredoka (OFL, bundled) owns the "Playzy" wordmark; Korean display = Pretendard 800; story reading = Gowun Batang (OFL, bundled). Gmarket Sans dropped. | Display/brand + story type 1:1 | **Resolved 2026-07-14** — all bundled, OFL-1.1 |
| D9 | Font glyph subsetting | Ship full Gowun Batang (~16 MB) now; subset to rendered glyphs later to cut app size | Release app size | Open — size optimization, not blocking |

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
