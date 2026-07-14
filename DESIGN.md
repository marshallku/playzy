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
| `bg.base` | `#FBF1E6` | `#1A2236` | App background (warm cream). **Never `#FFFFFF` / `#000000`.** |
| `bg.surface` | `#FFFCF7` | `#232C44` | Cards, sheets, fields |
| `bg.subtle` | `#F4EADA` | `#2A3550` | Grouped/inset areas, progress track |
| `bg.alt` | `#EADFCF` | `#4A4E69` | Disabled-button fill; dusky violet in dark |
| `border.hairline` | `#ECE0D0` | `#313A54` | 1px separators |
| `border.field` | `#E7DAC8` | `#313A54` | Input/chip outline (1.5px, §8) |

### 2.2 Brand

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `brand.primary` | `#5265C6` | `#8091E4` | Primary actions, selected state, "bedtime sky" |
| `brand.primaryPressed` | `#43539F` | `#7C93E8` | Pressed/active |
| `brand.primarySubtle` | `#E7ECF9` | `#2E3F63` | Tinted button bg, chips, info banner |
| `brand.secondary` | `#EC9086` | `#E8A79D` | Warmth accents (coral) |
| `brand.accent` | `#F3C64B` | `#FFE082` | 10% pops, CTAs, stars/moon-glow (moon yellow) |

> ⚠️ **D4 (open):** final brand primary hue and full 50–900 tonal ramps need a
> designer. `#5265C6` is a periwinkle deep enough to pass WCAG AA (≈5.2:1) with
> white button text. Any designer revision **must keep ≥4.5:1 with
> `text.onBrand`.** Cheap to swap within that constraint.

### 2.3 Text

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `text.primary` | `#2C2A31` | `#E9E2D3` | Headlines, body. Dark = moon-glow cream, never bright white |
| `text.secondary` | `#4A4750` | `#A6ADC0` | Supporting (also on tinted cards) |
| `text.tertiary` | `#736A60` | `#979FB2` | Hints, disabled |
| `text.onBrand` | `#FFFFFF` | `#1A2236` | Text on `brand.primary` fill |

> **Note (AA):** `text.tertiary` is **darker than the reference mockup's soft
> `#9C948A`** (which is only ≈2.7:1 on cream). Hint text renders at 14px, so
> the token is darkened to `#736A60` (≈4.75:1) to clear AA (§2.5). Same reason
> the night supporting tones are lightened to clear AA on the night **surfaces**
> (cards), not just `bg.base` — e.g. roster-card captions.

### 2.4 Semantic (soft, desaturated — never clinical)

| Token | Light | Dark |
| --- | --- | --- |
| `status.success` | `#7CBF9E` | `#8FD1AE` |
| `status.warning` | `#F2C14E` | `#F5D06F` |
| `status.error` | `#B0453E` | `#F0A3A3` |
| `status.info` | `#8FB8DE` | `#A5C8E8` |

> `status.error` (light) is deeper than the other semantics because it is the
> one rendered as **body text** (load-failure / retry copy) on the cream base —
> a soft pastel red fails AA there. The others are used as fills/icons.

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
| Display | **Pretendard** (800) | Pretendard | Big Korean titles (e.g. "동주의 밤") — heavy weight, not a separate face |
| Brand wordmark | — | **Fredoka** | The "Playzy" wordmark **only** — too characterful for anything else |
| Story body | **Gowun Batang** (serif) | Gowun Batang / Georgia | A warm Korean serif for read-aloud — a storybook feel that sets reading apart from UI |

> **Story serif (was: "no Korean serif"):** the earlier system used sans for
> story text, reasoning Korean has no serif-reading tradition. This is
> **reversed** — Korean *does* have a batang (바탕/명조) reading tradition, and a
> warm serif (Gowun Batang) makes the reading surface feel like a storybook,
> distinct from the operator UI. It is used **only** for `storyBody`/`storyTitle`.

**Bundling status:** all three families are **bundled** and OFL-1.1
(`app/assets/fonts/`, see `NOTICE.md`): Pretendard (variable), Gowun Batang
(Regular + Bold), Fredoka (variable, wordmark only). Gmarket Sans is dropped
(D8 resolved — Fredoka owns the wordmark). Gowun Batang adds ~16 MB; glyph
subsetting is a tracked size follow-up (`docs/planning/90`).

### 3.2 Type scale (8pt-aligned)

| Token | Size | Line-height | Weight | Use |
| --- | --- | --- | --- | --- |
| `brand` | 34 | 40 | 700 | "Playzy" wordmark (Fredoka) — brand only |
| `display` | 34 | 40 | 800 | Big Korean titles, hero (Pretendard) |
| `h1` | 28 | 36 | 700 | Screen titles |
| `h2` | 22 | 30 | 700 | Section / funnel headers |
| `h3` | 18 | 26 | 700 | Card / group titles |
| `body` | 16 | 24 | 400 | Default UI text |
| `bodySm` | 14 | 20 | 400 | Secondary |
| `caption` | 12 | 16 | 500 | Labels, meta |
| `button` | 16 | — | 700 | Button labels |
| `storyBody` | 20 | 1.85× | 400 | **Story reading (Gowun Batang) — scalable 18→28** |
| `storyTitle` | 26 | 34 | 700 | Chapter / story title (Gowun Batang) |

- **Reader font-size slider (18–28pt)** is required, and separate from (adds to)
  iOS Dynamic Type support.
- Story reading line length ~30–40 characters; generous 1.85 line-height.
- **Weights** are bumped over the earlier scale (h2/h3/button 600→700, display
  700→800) to match the reference's more confident headings. `body` stays 400 —
  paragraph legibility over weight (§1, principle 6); the reference's 500 body
  is an intentional non-adoption.

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
| `radius.sm` | 12 | small controls |
| `radius.chip` | 14 | selection chips |
| `radius.md` | 16 | inputs, small cards |
| `radius.lg` | 20 | cards |
| `radius.xl` | 24 | sheets, modals |
| `radius.2xl` | 32 | hero panels |
| `radius.pill` | 999 | primary buttons |
| `radius.circle` | 50% | avatars, icon buttons, mascot frame |

### 5.2 Shadows — soft, **color-tinted** (never grey/black)

| Token | Value (light) |
| --- | --- |
| `shadow.sm` | `0 2px 8px rgba(82,101,198,0.10)` |
| `shadow.md` | `0 8px 24px rgba(82,101,198,0.12)` |
| `shadow.lg` | `0 16px 40px rgba(82,101,198,0.14)` |

(Tint = `brand.primary` light `#5265C6` = rgb(82,101,198).)

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
  CTAs, `button` type, `brand.primary` fill, `text.onBrand`. Rests on a soft
  `shadow.md` tint (light only); press: scale **0.97** + dips to `shadow.sm`;
  night is flat (no dark shadow, §5.2).
- **Secondary:** pill, `brand.primarySubtle` fill, **`brand.primaryPressed`
  label (light) / `text.primary` label (night)** — the plain `brand.primary`
  label is only 4.4:1 on the light tint (fails AA), so use the darker pressed
  tone; in night the periwinkle is too dark on the tint, so the cream text wins.
- **Text/ghost:** no fill, `brand.primary` label, for low-emphasis actions.
- Min tap target **44×44pt**; disabled = `bg.alt` fill + `text.tertiary` label.

### Inputs

- Height ≥ 52px, `radius.md`, generous inner padding (`space.lg`), `bg.surface`
  fill, **`border.field` at 1.5px**. Focus = `brand.primary` ring (no harsh
  outline). Labels above field; error text in `status.error` + icon.

### Selection chips / cards (theme picker — a core screen)

- Big tappable cards or pill chips with **illustration/emoji + label**.
- **Unselected:** `bg.surface` fill, `border.field` (1.5px), `radius.chip` (14).
- **Selected:** `brand.primarySubtle` fill + `brand.primary` border (1.5px) +
  a `brand.primary` checkmark. The **label stays `text.primary`** in both modes
  (AA-safe on both fills); selection is cued by fill + border + ✓, never color
  alone (§2.5). Subtle scale (1.02) optional.
- **Multi-select** supported. Comfortable tap target (Material's ≥48px, above
  the §9 ≥44 minimum); generous spacing (≥8px between).
- **Boundary contrast (WCAG 1.4.11):** the *unselected* chip's soft
  `border.field` is intentionally low-contrast (the calm aesthetic, §1) — the
  chip is identified by its pill shape + label, so the boundary is not the sole
  identifier. The *selected* state is indicated by cues that DO clear 3:1: the
  `brand.primary` border (≈5:1 on the fill) and the checkmark, plus the tint
  fill. So selection is never conveyed by a sub-3:1 signal.

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
- **Contrast AA** on every *active* pair (see §2.5). Test, don't assume —
  pastels fail. The token file darkens the reference mockup's soft `#9C948A`
  text, its pastel error, and its light reader toggle so each clears AA; locked
  by contrast tests. **Disabled** controls are the one exception — WCAG 1.4.3
  exempts inactive components, and low contrast is the *correct* "inactive"
  affordance, so the disabled button (`bg.alt` + `text.tertiary`) is
  deliberately de-emphasized rather than forced to 4.5:1.
- **Component boundaries (WCAG 1.4.11):** inputs and unselected chips keep the
  soft warm `border.field` (calm aesthetic, §1) — this is conformant because the
  control is identified by its **label/hint + fill**, not by the boundary alone,
  and every *state* signal (input focus ring, selected-chip primary border +
  checkmark) does clear 3:1. Text contrast (§2.5) is the harder, tested bar.
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
│   ├── colors.dart      # AppColors.light / AppColors.night — incl. borderField (§2)
│   ├── typography.dart  # AppTypography — uiFamily/storyFamily/brandFamily, brand style (§3)
│   ├── spacing.dart     # AppSpacing (§4)
│   ├── radius.dart      # AppRadius — incl. chip=14 (§5.1)
│   ├── borders.dart     # AppBorders — hairline/field=1.5/focus (§8)
│   ├── shadows.dart     # AppShadows — primary-tinted (§5.2)
│   └── motion.dart      # AppMotion (§7)
└── theme.dart           # ThemeData(light/dark): input + chip themes from tokens
```

Rule: **components never hardcode a hex/number** — they read a token. Changing a
brand color or radius is a one-line token edit that propagates everywhere,
including SDUI-rendered components and (via export) web surfaces.
