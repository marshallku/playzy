# ADR 0001 — Repository shape & AI backend abstraction

- **Status**: Accepted
- **Date**: 2026-07-11
- **Context owner**: Playzy

## Context

Playzy generates children's stories with an LLM. The initial AI backend is
`~/dev/kagi` — a **reverse-engineered, unofficial** Go client for Kagi
Assistant. Its own README warns it "may break at any time." The user has stated
the backend is expected to be **swapped for a different AI service later**.

Two hard facts drive this ADR:

1. **kagi is not shippable inside a mobile app.** It is a single-user local
   CLI/HTTP server that authenticates with a personal Kagi session/keyring on
   the developer's machine. A published iOS app cannot embed it, and we must
   not ship personal credentials.
2. **The AI provider will change.** kagi is a prototyping convenience, not the
   production dependency.

## Decision

### 1. Insert a Playzy backend (proxy/gateway) between app and AI

```
┌────────────┐      HTTPS/JSON      ┌──────────────────┐      provider call     ┌──────────┐
│ Flutter app│ ───────────────────▶ │ Playzy backend   │ ─────────────────────▶ │ kagi     │
│ (iOS first)│   POST /v1/stories   │ (AI gateway)     │   POST /chat (kagi)    │ (dev now)│
└────────────┘                      │  + prompt builder│                        └──────────┘
                                    │  + provider iface│      later ▶ OpenAI / Anthropic / …
                                    └──────────────────┘
```

The app never speaks to an AI provider directly. It calls a **stable Playzy
story API**. Behind that API, a `StoryProvider` interface is implemented per
backend (`KagiProvider` now, others later). Swapping providers is a
server-side change with zero app release.

Benefits: keeps secrets server-side, lets us change providers without an App
Store review cycle, centralizes the prompt engineering, and enables
rate-limiting / the free-tier quota to be enforced where it can't be bypassed.

### 2. The provider seam (server-side)

```
StoryProvider (interface)
  generateStory(StoryRequest) -> StoryResult          // unary
  streamStory(StoryRequest) -> Stream<StoryChunk>     // optional streaming

KagiProvider    implements StoryProvider  // wraps kagi POST /chat, /chat/stream
OpenAIProvider  implements StoryProvider  // future
```

`StoryRequest` is provider-agnostic (child profile + chosen situations + story
options). The provider is responsible for turning that into a prompt and
parsing the model's output into a structured `StoryResult`.

### 3. The app-side seam

The Flutter app talks to `StoryApi` (our backend), never to a provider. A local
`FakeStoryApi` backs widget tests and offline development so the UI can be built
and tested before the backend exists.

## Repository layout

```
playzy/
├── DESIGN.md                # design system (root, per convention)
├── docs/                    # this directory
├── app/                     # Flutter app (iOS first)
├── backend/                 # Playzy AI gateway (thin; wraps kagi for now)
└── web/                     # experimental web / SDUI surfaces (later)
```

`backend/` may start as the thinnest possible layer — even a documented adapter
in front of `kagi serve` — but the **API contract** the app depends on is fixed
here so the app is never coupled to kagi's shape.

## Consequences

- The app is decoupled from the AI provider from day one (good).
- We carry a backend service earlier than a pure-client app would (accepted
  cost; unavoidable given kagi can't ship client-side).
- During early local development the "backend" can be `kagi serve` fronted by a
  small adapter; the app targets the stable contract regardless.

## Open questions (tracked in planning/90-open-decisions.md)

- Where the backend is hosted for the real launch (kagi is dev-only).
- Whether stories are streamed to the app (SSE) or delivered unary first.
- Illustration generation (text-only MVP vs. AI images) — see MVP scope.
