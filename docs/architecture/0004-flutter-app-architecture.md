# ADR 0004 — Flutter app architecture

- **Status**: Accepted
- **Date**: 2026-07-11

## Context

Phase 5 builds the Flutter iOS app. We need a layering, state-management, and
folder convention that is clear, testable, and keeps the swappable seams (AI
gateway, payments — ADR 0001/0002) clean. The user has no Flutter-specific
profile rules, but the general profile applies: **layered architecture, single
responsibility, clarity over cleverness, test what fails, Rule of Three.**

## Decision

### Layering (feature-first, layered within)

```
app/lib/
├── design/                 # design tokens + ThemeData (mirrors DESIGN.md)
├── core/                   # cross-cutting: result type, env, http, errors, router
├── data/                   # data layer — API clients + models + repositories
│   ├── story/              #   StoryApi (interface) + HttpStoryApi + FakeStoryApi
│   ├── payment/            #   PaymentGateway (interface) + impls + Fake
│   └── profile/            #   local child-profile storage
├── domain/                 # pure models + entities (no Flutter, no IO)
│   ├── child_profile.dart
│   ├── situation.dart
│   └── story.dart
├── features/               # UI, feature-first
│   ├── onboarding/
│   ├── child_profile/
│   ├── situation_picker/   # (SDUI-rendered — ADR 0003)
│   ├── story_reader/
│   └── paywall/
├── sdui/                   # the single SDUI renderer (ADR 0003 Tier A)
├── webview/                # the single WebView + JS bridge wrapper (Tier B)
└── main.dart
```

- **domain** is pure Dart (unit-testable without Flutter).
- **data** hides every external dependency behind an interface + a `Fake*` for
  tests and offline dev. The app depends on interfaces, never concrete SDKs.
- **features** hold widgets + their view-model/controllers only.

### State management: **Riverpod**

Chosen over Bloc/Provider for: compile-safe dependency injection (great for
swapping `Fake*` ↔ real impls in tests), low boilerplate, testability, and
clear separation of async state (`AsyncValue`). Providers wire the composition
root — e.g. `storyApiProvider` returns `FakeStoryApi` in tests, `HttpStoryApi`
in production.

Relaxation clause (decision framework): if Riverpod fights a specific screen,
local `setState` is acceptable for leaf widgets with no shared state.

### Error handling: typed exceptions at the async seam + `AsyncValue`

Decision (revised): for **async** data-layer calls, the seam throws a **typed
exception** (e.g. `StoryApiException`) and Riverpod's `AsyncValue` /
`AsyncValue.guard` carries the error to the UI. `AsyncValue` *is* the
Result-equivalent for async in this stack — it captures data/loading/error
uniformly — so a hand-rolled `Result<T>` around every `Future` would fight the
framework, not help it.

A small sealed `Result<T>` is reserved for **synchronous, multi-step** flows
where tuple-style branching is genuinely clearer (matching the profile's "to"
utility spirit) — introduced only where such a flow appears (Rule of Three), not
pre-emptively. Errors are always logged with context, never swallowed
(anti-pattern #5). Typed exceptions keep error context (which class, which
message) rather than a bare throw.

### Navigation: `go_router`

Declarative, deep-link-ready (needed for payment return URLs and future
sharing), testable route table in `core/router`.

### Testing strategy (profile: test what fails, not coverage %)

- **Unit tests** for `domain` logic and the prompt/parse boundary in providers.
- **Data-layer tests** against `Fake*` and against parsing real API JSON
  fixtures (story parsing, SDUI parsing — these are where bugs hide).
- **Widget tests** for the core flows (child profile form validation, situation
  selection, reader font-size scaling, paywall gating) using `Fake*` gateways.
- Skip: trivial widget golden tests, framework behavior, throwaway UI.
- `flutter analyze` + `dart format` are the automated gates (mirrors the
  ESLint/Prettier discipline). Line length and quotes follow Dart conventions
  (Dart tooling is opinionated — we defer to `dart format`, not the TS rules).

### Conventions

- **No hardcoded colors/sizes in widgets** — always a design token (DESIGN.md
  §12).
- Files: `snake_case.dart` (Dart convention). Types: `PascalCase`. This is the
  one place we follow the language's convention over the profile's TS naming,
  because Dart tooling and the ecosystem assume it.
- Comments terse; context goes in `docs/`.

## Consequences

- Clean swap points for AI backend and payments; `Fake*` impls let the whole UI
  be built and tested before the backend exists.
- Riverpod + go_router + a small Result type is a conventional, boring,
  maintainable Flutter stack — deliberately not clever.
- One SDUI renderer and one WebView bridge (no scattering) per ADR 0003.
