# Story prompts

`story_author_system.md` is the **single source of truth** for the story
generator's system prompt (persona, child-safety rules, input format, age/mood
definitions, writing style, and the strict JSON output contract). It is
versioned here so the product contract stays reviewed and testable (ADR 0001).

It is used two ways, both from this one file:

1. **Embedded into the backend** (`//go:embed` in `prompt.go`). On the base-model
   path (no Kagi profile configured) `buildStoryPrompt` prepends it to the
   per-request materials, so a bare model is fully self-contained.
2. **Seeds the Kagi profile** (a custom assistant). In profile mode
   (`KAGI_PROFILE_ID` set) the profile's instructions **are** the system prompt,
   so the backend sends only the per-request materials (`buildStoryMaterials`) —
   the persona isn't re-sent every request.

The per-request payload is always just:

```
[이야기 재료]   (child materials — user-derived, untrusted)
[오늘의 설정]   (age band / mood / target page count — backend-derived labels)
```

## Keep the profile in sync

When you edit this file, the embedded copy updates on the next backend build, but
a Kagi profile does **not** — update it explicitly so the two don't drift:

```bash
kagi assistants update <KAGI_PROFILE_ID> --prompt backend/prompts/story_author_system.md
```

(Create a fresh one with `kagi assistants create -n "Playzy 동화작가" -m claude-5-sonnet \
  --no-internet --no-personalize --prompt backend/prompts/story_author_system.md`.)
