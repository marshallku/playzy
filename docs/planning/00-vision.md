# Vision

## One line

**Playzy turns a parent's few taps into a personalized bedtime story for their
young child.**

## The problem

Parents of infants and toddlers (0–6) read the same handful of picture books on
repeat. Generic stories don't use the child's name, their favorite animal, the
sibling they're jealous of, or the specific thing they're struggling with this
week (potty training, a new daycare, fear of the dark). Writing a custom story
every night is not realistic for a tired parent.

## The product

1. **Set up the child once** — name, age, a few interests / favorite things.
2. **Pick tonight's situations** — a small set of tappable themes/moments
   (e.g. "going to sleep", "sharing toys", "visiting grandma", "brushing
   teeth", "a brave little adventure").
3. **Generate** — the app produces a short, warm, age-appropriate story
   starring the child, tuned to the chosen situations.
4. **Read together** — a calm, legible reader view for bedtime.

The first few stories are **free**; beyond that requires payment (see
`planning/20-monetization.md`).

## Who it's for

- **Primary user (operator):** the parent — usually at night, one-handed,
  tired, low patience for friction.
- **Audience of the content:** the child (0–6) — story tone, vocabulary,
  length, and warmth are tuned to them.

Design implication: the UI is a **calm, fast, low-friction parent tool** with a
**warm, storybook soul**. Not a loud, gamified kids' app.

## Principles

- **Bedtime-first.** Works beautifully in a dark room, at low brightness, with
  a sleeping baby on one arm. Night mode is a first-class citizen, not an
  afterthought.
- **Fast to a story.** The path from open → finished story is short. Setup is
  remembered; nightly use is a few taps.
- **Warm, safe, age-appropriate.** Content guardrails matter more here than
  almost anywhere — this is content for very young children.
- **Swappable guts.** The AI provider and the payment provider are behind
  interfaces (ADR 0001, ADR 0002). Product decisions we're unsure about are
  built to be replaced, not to be permanent.

## Non-goals (for now)

- Not a social network / sharing community (maybe later).
- Not a full animated interactive game.
- Not a general-purpose kids' education platform.

## Naming

Working product name: **Playzy** (repo name). Not final; treat as a placeholder
that's cheap to change (kept out of hardcoded strings where practical).
