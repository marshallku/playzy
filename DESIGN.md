# Playzy — Design System

> The single source of truth for how Playzy looks and feels. From padding and
> border-radius up to the overall aesthetic direction. Backed by
> `docs/research/design.md`; rationale for non-obvious choices lives in
> `docs/design/`.
>
> **Implementation:** these tokens are mirrored 1:1 in Flutter under
> `app/lib/design/` (see §12). Web/SDUI surfaces import the same values so brand
> stays consistent across native and web (ADR 0003).

---

## 1. Design principles

1. **Bedtime-first.** The signature scenario is a tired parent, in a dark room,
   one-handed, at 2am. Night mode is first-class; nothing bright flashes.
2. **Two moods, one system.** A calm, confident **parent-operator UI** and a
   warm, illustration-forward **story-reading mode** share tokens but differ in
   density and drama.
3. **Soft & safe.** No pure black, no pure white. Rounded everything — sharp
   angles read as threat, rounded reads as safe.
4. **Calm over loud.** Low-stimulation, wind-down. Gentle motion, muted pops.
5. **60-30-10 color.** ~60% light neutral background, ~30% dominant hue, ~10%
   accent. Playful, not chaotic.
6. **Legible by default.** This audience benefits from readability far more than
   from novelty. Big type, big targets, generous space.

---

## 2. Color

Every color has a **light** and a **dark (night)** value. Names are semantic
(role), not literal (hue), so re-theming is a token swap.

### 2.1 Neutrals & backgrounds

| Token | Light | Dark (night) | Use |
| --- | --- | --- | --- |
| `bg.base` | `#FFF8F0` | `#1B2838` | App background. **Never `#FFFFFF` / `#000000`.** |
| `bg.surface` | `#FEFCF8` | `#24334A` | Cards, sheets |
| `bg.subtle` | `#F5EEE4` | `#2C3E50` | Grouped/inset areas |
| `bg.alt` | `#EFE7DB` | `#4A4E69` | Alternate surface, dusky violet in dark |
| `border.hairline` | `#EAE0D3` | `#33445E` | 1px separators |

### 2.2 Brand

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `brand.primary` | `#4E6FBC` | `#91A7E8` | Primary actions, selected state, "bedtime sky" |
| `brand.primaryPressed` | `#3F5EA8` | `#7C93E8` | Pressed/active |
| `brand.primarySubtle` | `#E9EFFA` | `#2E3F63` | Tinted button bg, chips |
| `brand.secondary` | `#F6B6B6` | `#E29A9A` | Warmth accents (dusty rose) |
| `brand.accent` | `#F8C291` | `#FFE082` | 10% pops, CTAs, stars/moon-glow |

> ⚠️ **D4 (open):** final brand primary hue and full 50–900 tonal ramps need a
> designer. `#4E6FBC` is a periwinkle deep enough to pass WCAG AA (≈4.9:1) with
> white button text — the research's softer `#6A89CC` fails AA, so we darkened
> it. Any designer revision **must keep ≥4.5:1 with `text.onBrand`.** Cheap to
> swap within that constraint.

### 2.3 Text

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `text.primary` | `#2E3A4D` | `#E8D5B7` @ 90% | Headlines, body. Dark = moon-glow cream, never bright white |
| `text.secondary` | `#6B7688` | `#B7A98F` | Supporting |
| `text.tertiary` | `#9AA3B2` | `#8A7F6B` | Hints, disabled |
| `text.onBrand` | `#FFFFFF` | `#1B2838` | Text on `brand.primary` fill |

### 2.4 Semantic (soft, desaturated — never clinical)

| Token | Light | Dark |
| --- | --- | --- |
| `status.success` | `#7CBF9E` | `#8FD1AE` |
| `status.warning` | `#F2C14E` | `#F5D06F` |
| `status.error` | `#E88B8B` | `#F0A3A3` |
| `status.info` | `#8FB8DE` | `#A5C8E8` |

### 2.5 Color rules

- **Contrast:** WCAG AA — body ≥ 4.5:1, large text ≥ 3:1. Soft pastels fail
  easily; **every** semantic-on-surface and text-on-tint pair must be checked.
- **Don't rely on color alone** for state — pair with icon or label.
- **Night mode:** low overall luminance, warm text, no bright-white flashes
  (protects melatonin and doesn't wake the child).

---

## 3. Typography

### 3.1 Families

| Role | Korean | Latin | Notes |
| --- | --- | --- | --- |
| UI / body | **Pretendard** | SF Pro (system) / Nunito | Workhorse. High legibility. |
| Display / brand | **Gmarket Sans** | Fredoka / Baloo 2 | App name, big titles **only** — too characterful for paragraphs |
| Story body | **Pretendard** | Georgia (serif) | Korean has no serif-reading tradition → clean sans. Latin story text may use a readable serif. |

**Bundling status:** Pretendard (variable, OFL) **is bundled**
(`app/assets/fonts/`). Gmarket Sans is **not** bundled — its license needs
review before redistribution, so display/brand text falls back to Pretendard
until a licensed asset is dropped in (tracked in `docs/planning/90` — fonts).

### 3.2 Type scale (8pt-aligned)

| Token | Size | Line-height | Weight | Use |
| --- | --- | --- | --- | --- |
| `display` | 34 | 40 | 700 | App name, hero |
| `h1` | 28 | 36 | 700 | Screen titles |
| `h2` | 22 | 30 | 600 | Section headers |
| `h3` | 18 | 26 | 600 | Card titles |
| `body` | 16 | 24 | 400 | Default UI text |
| `bodySm` | 14 | 20 | 400 | Secondary |
| `caption` | 12 | 16 | 500 | Labels, meta |
| `button` | 16 | — | 600 | Button labels |
| `storyBody` | 20 | 32 | 400 | **Story reading — scalable 18→28** |
| `storyTitle` | 26 | 34 | 700 | Chapter / story title |

- **Reader font-size slider (18–28pt)** is required, and separate from (adds to)
  iOS Dynamic Type support.
- Story reading line length ~30–40 characters.

---

## 4. Spacing & layout

**8pt grid with 4pt half-steps.** Named scale:

| Token | px |
| --- | --- |
| `space.xs` | 4 |
| `space.sm` | 8 |
| `space.md` | 12 |
| `space.lg` | 16 |
| `space.xl` | 20 |
| `space.2xl` | 24 |
| `space.3xl` | 32 |
| `space.4xl` | 40 |
| `space.5xl` | 48 |
| `space.6xl` | 64 |

- **Screen edge margin: 20–24px** (`space.xl`–`space.2xl`) — not 16. Calm apps
  breathe.
- **Card inner padding: 16–20px.** **Section gaps: 24–32px.**
- **Reader:** wide margins, single column.

---

## 5. Shape (radius & elevation)

### 5.1 Radius

| Token | px | Use |
| --- | --- | --- |
| `radius.sm` | 12 | chips, small controls |
| `radius.md` | 16 | inputs, small cards |
| `radius.lg` | 20 | cards |
| `radius.xl` | 24 | sheets, modals |
| `radius.2xl` | 32 | hero panels |
| `radius.pill` | 999 | primary buttons, selection chips |
| `radius.circle` | 50% | avatars, icon buttons, mascot frame |

### 5.2 Shadows — soft, **color-tinted** (never grey/black)

| Token | Value (light) |
| --- | --- |
| `shadow.sm` | `0 2px 8px rgba(78,111,188,0.10)` |
| `shadow.md` | `0 8px 24px rgba(78,111,188,0.12)` |
| `shadow.lg` | `0 16px 40px rgba(78,111,188,0.14)` |

(Tint = `brand.primary` light `#4E6FBC` = rgb(78,111,188).)

- **Night mode:** drop shadows nearly vanish; use a slightly lighter surface +
  faint glow to convey elevation instead of dark shadows.

### 5.3 Blobs

Decorative organic blobs (asymmetric radius, e.g. `40% 60% 55% 45%`) as
**background décor** behind headers/illustrations — a genre hallmark. Décor
only, never content containers.

---

## 6. Iconography & illustration

- **Icons:** rounded, filled or thick rounded-stroke (2–2.5px, rounded caps &
  joins). Avoid thin, sharp line icons. Base set = SF Symbols (rounded weight).
- **Illustration is the product's soul.** For any illustrator: build from basic
  rounded shapes, fewest shapes necessary, no pointy shapes, bold/bouncy/bright.
  Line work uses dark navy, **never pure black**.

> ⚠️ **Needs a professional designer / illustrator** (isolated behind asset
> slots so it drops in without code changes):
> 1. Mascot / brand character — commission, don't AI-generate the hero.
> 2. In-story illustration style bible (+ open decision **D3**: AI-per-story art
>    vs. fixed illustrated frame with generated text).
> 3. Full 50–900 tonal color ramps + final brand hue (**D4**).
> 4. Custom icon set beyond SF Symbols.
> 5. App icon + onboarding hero art.

---

## 7. Motion

Gentle, slow, purposeful — a wind-down app.

| Token | Value | Use |
| --- | --- | --- |
| `motion.fast` | 150ms | taps, chip select, toggles |
| `motion.base` | 300ms | most transitions |
| `motion.slow` | 500ms | screen transitions, page-turn |
| `motion.ambient` | 120s | background star/cloud drift |
| `motion.ease` | `cubic-bezier(0.25, 0.1, 0.25, 1)` | default easing |

- **Story page-turn** is the signature interaction: gentle horizontal slide or
  soft page-curl, ~400–500ms, ease-in-out. **No bounce** in the reader (save
  bounce for playful daytime moments).
- **Ambient:** imperceptibly slow drift behind the reader — soothes, doesn't
  distract.
- **Auto-fade reader chrome** after ~30s so only story + art remain.
- Use **Lottie/Rive** for mascot idle, the "story is being written" loader, and
  celebration moments.
- **Honor iOS Reduce Motion** → cross-fades instead of slides.

---

## 8. Core components

### Buttons

- **Primary:** pill (`radius.pill`), height **52–56px**, full-width for main
  CTAs, `button` type, `brand.primary` fill, `text.onBrand`. Press: scale 0.97 +
  `shadow.sm` tint.
- **Secondary:** pill, `brand.primarySubtle` fill, `brand.primary` label.
- **Text/ghost:** no fill, `brand.primary` label, for low-emphasis actions.
- Min tap target **44×44pt**; disabled uses `text.tertiary`.

### Inputs

- Height ≥ 52px, `radius.md`, generous inner padding (`space.lg`), `bg.surface`
  fill, `border.hairline`. Focus = `brand.primary` ring (no harsh outline).
  Labels above field; error text in `status.error` + icon.

### Selection chips / cards (theme picker — a core screen)

- Big tappable cards or pill chips with **illustration/emoji + label**.
- **Selected:** `brand.primary` border/fill tint + subtle scale (1.02).
- **Multi-select** supported. Min height 56px; generous spacing (≥8px between).

### Story reader

- Single column; full-bleed illustration (top or background) with `storyBody`
  over a scrim when overlaid.
- Page-turn navigation; auto-fading chrome.
- Controls: **font-size slider, brightness, night-mode toggle**, optional TTS
  play. In night mode these controls are **≥80px** (used in the dark,
  half-asleep).

### Sheets / modals

- Bottom sheets, `radius.xl` top corners, drag handle, `bg.surface`.

---

## 9. Accessibility

- **Tap targets ≥ 44×44pt**; **night-reader controls ≥ 80px**. ≥8px between
  targets to prevent rage-taps.
- **Contrast AA** on every pair (see §2.5). Test, don't assume — pastels fail.
- **Dynamic Type** supported; reader slider supplements it.
- **Reduce Motion** honored.
- Never encode state in color alone.

---

## 10. Theming & modes

- **Light / Night** are peers, both fully specified above. Night is not a
  desaturated afterthought — it's the hero scenario.
- Mode follows system by default with an in-app override; the **reader** can be
  forced to night independently of the app chrome (read in the dark even if the
  phone is in light mode).

---

## 11. What is intentionally deferred

Tracked in `docs/planning/90-open-decisions.md`. Summary: mascot, in-story
illustration style, final tonal ramps, custom icon set, app icon, hero art —
all isolated behind tokens/asset slots. TTS/read-aloud is post-MVP.

---

## 12. Token implementation map (Flutter)

```
app/lib/design/
├── tokens/
│   ├── colors.dart      # AppColors.light / AppColors.dark (§2)
│   ├── typography.dart  # AppTypography scale (§3)
│   ├── spacing.dart     # AppSpacing (§4)
│   ├── radius.dart      # AppRadius (§5.1)
│   ├── shadows.dart     # AppShadows (§5.2)
│   └── motion.dart      # AppMotion (§7)
└── theme.dart           # ThemeData(light/dark) assembled from tokens
```

Rule: **components never hardcode a hex/number** — they read a token. Changing a
brand color or radius is a one-line token edit that propagates everywhere,
including SDUI-rendered components and (via export) web surfaces.
