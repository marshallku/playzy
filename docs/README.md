# Playzy — Documentation

Playzy is an iOS-first mobile app that generates personalized fairy tales for
infants and toddlers (영유아, ages 0–6). A parent enters their child's profile,
picks a few situations/themes, and the app produces a bespoke bedtime story.

This `docs/` directory holds **all context and judgment that does not fit in a
short code comment**. Code comments stay terse; the "why" lives here.

## Map

| Dir | What lives here |
| --- | --- |
| `research/` | Competitor, design, and payments research (inputs to planning) |
| `planning/` | Product vision, MVP scope, roadmap, open decisions |
| `architecture/` | Architecture Decision Records (ADRs) — numbered, immutable-ish |
| `design/` | Design-system rationale that backs the root `DESIGN.md` |

The design system itself is the root-level **`DESIGN.md`** (per project
convention). `docs/design/` holds the longer-form reasoning behind it.

## Reading order (for a new contributor)

1. `planning/00-vision.md` — what we're building and for whom
2. `planning/10-mvp-scope.md` — what's in / out of the first iOS launch
3. `architecture/0001-repo-and-ai-backend.md` — how the pieces fit
4. `../DESIGN.md` — the design system
5. `research/*` — the evidence base

## Working conventions

- **Comments**: one line, only when the code isn't self-evident. Everything
  longer goes in `docs/`.
- **Decisions**: anything non-obvious or reversible-with-cost becomes an ADR in
  `architecture/`. ADRs are append-only; supersede rather than rewrite.
- **Swappable seams**: the AI backend and the payment provider are both behind
  interfaces on purpose (see ADR 0001 and 0002). Treat them as replaceable.
