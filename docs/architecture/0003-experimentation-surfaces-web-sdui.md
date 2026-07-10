# ADR 0003 — Experimentation surfaces: WebView & Server-Driven UI

- **Status**: Accepted
- **Date**: 2026-07-11

## Context

The user wants parts of the app that need frequent iteration or A/B
experimentation to be shippable **without an App Store release cycle**, via
either a **WebView** (render a web page inside the app) or **Server-Driven UI**
(the server sends a UI description the app renders natively).

iOS review turnaround (hours-to-days) makes native releases a poor fit for:
- Tuning the paywall / pricing presentation.
- Iterating on the "situation picker" content (the catalog of themes grows and
  reorders often).
- Marketing / seasonal / promotional surfaces.
- Onboarding copy and order experiments.

But native is the right call for the core, latency-sensitive, offline-capable
flows (child profile, the story reader).

## Decision

Adopt a **two-tier experimentation strategy** and mark each surface explicitly.

### Tier A — Server-Driven UI (SDUI) for structured, native-rendered content

Use SDUI where the *content and arrangement* change often but the *widget
vocabulary* is small and known. Prime example: the **situation/theme picker**.

- The backend returns a JSON document describing sections, chips, cards, and
  their actions.
- The app has a small, fixed **SDUI renderer** that maps a whitelisted set of
  component types (`section`, `chip_group`, `card`, `banner`, `spacer`) to
  native Flutter widgets styled by the design system.
- New themes, reordering, seasonal sets, and copy ship as a **backend data
  change** — no app release.
- The renderer is intentionally *limited* (not a general HTML engine): it stays
  on-brand because every component is a design-system widget, and it stays safe
  because the app only renders known types.

Contract lives at `backend` + mirrored Dart models in `app`. Versioned with a
`schemaVersion`; unknown component types degrade gracefully (skipped, logged).

### Tier B — WebView for free-form / vendor surfaces

Use a WebView where the content is genuinely web-shaped or vendor-driven:
- The **paywall / pricing** experiment surface (rapid copy + layout A/B).
- Any **payment** flow that is itself web-based (e.g. Toss Payments widget is
  WebView-based — see ADR 0002).
- Legal (terms/privacy), help, and marketing pages.

WebView pages live in `web/` (a small static site / experiment host),
communicate with native via a **typed JS bridge** (postMessage) for actions
like "purchase succeeded", "close", "generate story". The bridge surface is
small and documented so native and web stay in sync.

### What stays fully native (no experimentation layer)

- Child profile setup and storage.
- The **story reader** (bedtime-critical, must work offline, must be buttery).
- Navigation shell, auth/session.

## Boundaries & rules

- **One renderer, one bridge.** Do not scatter ad-hoc WebViews or bespoke JSON
  parsers. All SDUI goes through the single renderer; all WebViews through the
  single bridge wrapper.
- **Design system is the source of truth.** SDUI components render as
  design-system widgets; web surfaces import the same tokens (exported from
  `DESIGN.md`) so brand stays consistent across native/web.
- **Graceful offline.** SDUI responses are cached; if the picker can't load,
  the app falls back to a bundled default catalog so a parent is never stuck.
- **Security.** WebView loads only our own allow-listed origins; the JS bridge
  validates every message against a typed schema.

## Consequences

- We can iterate on pricing, theme catalog, and onboarding copy server-side.
- Cost: two extra moving parts (an SDUI renderer + a web experiment host) and
  the discipline to keep their contracts versioned. Justified by the release
  cadence the user asked for.
- Areas the AI cannot design well (custom illustration, mascot, motion polish)
  are flagged in `DESIGN.md` and can be dropped into either tier later without
  re-architecting.
