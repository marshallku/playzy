# Research — Design language for a toddler bedtime-story app

> Gathered 2026-07-11. Inputs to `DESIGN.md`. Concrete tokens below are
> drop-in ready; items needing a human designer are flagged with ⚠️.

## Core framing

Two aesthetics must coexist because the **user is the parent** but the **theme
is child-bedtime**:

- **Parent-facing operator UI** (home, theme picker, settings, generation):
  clean, calm, confidence-inspiring, warm.
- **Story-reading mode** (the payoff): storybook/bedtime, illustration-forward,
  night-mode-friendly.

Recurring principles across high-quality apps studied (Headspace, Calm,
Duolingo ABC, Khan Academy Kids, Sago Mini, Pok Pok):

- **No pure black, no pure white.** Warmest neutral `#FFF8F0`, darkest a navy
  `#1B2838`. This one rule does the most for a soft/warm feel.
- **60-30-10 color ratio** — 60% light neutral bg, 30% dominant hue, 10% accent.
- **Rounded everything, no pointy shapes** (Duolingo shape language). Sharp
  angles read as threat; rounded reads as safe.
- **Calm over loud.** For a *bedtime* app, gentle, low-stimulation, wind-down.

## 1. Color

### Light theme (parent UI + daytime reading)

| Role | Hex | Notes |
| --- | --- | --- |
| `bg/base` | `#FFF8F0` | Warm cream. Never `#FFFFFF`. |
| `bg/surface` | `#FEFCF8` | Cards marginally brighter than base |
| `bg/subtle` | `#F5EEE4` | Grouped/inset areas |
| `primary` | `#6A89CC` | Soft periwinkle/blue — calm, "bedtime sky" |
| `primary/pressed` | `#5B77C0` | |
| `secondary` | `#F6B6B6` | Dusty rose/peach — warmth |
| `accent` | `#F8C291` | Apricot; 10% pops, CTAs, stars |
| `text/primary` | `#2E3A4D` | Deep navy-slate, NOT black |
| `text/secondary` | `#6B7688` | |
| `border/hairline` | `#EAE0D3` | |

Optional whimsy lavender: `#B8A4E0`.

### Dark / night theme (bedtime reading — critical, first-class)

| Role | Hex | Notes |
| --- | --- | --- |
| `bg/base` | `#1B2838` | Deep navy (not `#121212`) |
| `bg/surface` | `#24334A` | Cards/sheets |
| `bg/alt` | `#4A4E69` | Dusky violet-grey |
| `primary` | `#91A7E8` | Desaturated — saturated colors vibrate on dark |
| `accent/star` | `#FFE082` | Star-yellow / moon-glow warm counterpoint |
| `text/primary` | `#E8D5B7` @ 90% | Moon-glow warm cream, never bright white |
| `text/secondary` | `#B7A98F` | |

### Semantic (soft, desaturated — not clinical)

| Role | Light | Dark |
| --- | --- | --- |
| success | `#7CBF9E` | `#8FD1AE` |
| warning | `#F2C14E` | `#F5D06F` |
| error | `#E88B8B` | `#F0A3A3` |
| info | `#8FB8DE` | `#A5C8E8` |

⚠️ **Needs a designer:** final brand primary hue (periwinkle-calm vs coral-warm)
and full 50–900 tonal ramps per color. The above is a defensible start.

## 2. Typography

- **UI + headings:** rounded friendly sans. Latin: Fredoka/Baloo 2/Quicksand/
  Nunito or SF Pro Rounded (native iOS). **Korean: Pretendard** (workhorse for
  UI + Korean story body), **Gmarket Sans** for app name / big titles only.
- **Story body:** Latin favors a readable serif (Georgia / Bembo/Plantin Infant)
  set LARGE. **Korean has no serif-reading tradition → clean sans (Pretendard)**
  for Korean story text. Set 18–24pt with generous leading.

### Type scale (8pt-aligned)

| Token | Size / LH / Weight | Use |
| --- | --- | --- |
| `display` | 34 / 40 / 700 | App name, hero |
| `h1` | 28 / 36 / 700 | Screen titles |
| `h2` | 22 / 30 / 600 | Section headers |
| `h3` | 18 / 26 / 600 | Card titles |
| `body` | 16 / 24 / 400 | Default UI |
| `body-sm` | 14 / 20 / 400 | Secondary |
| `caption` | 12 / 16 / 500 | Labels |
| `button` | 16 / — / 600 | |
| `story-body` | **20 / 32 / 400** | Story reading (scalable 18→28) |
| `story-title` | 26 / 34 / 700 | Chapter/story title |

Ship a reader **font-size slider (18–28pt)** — non-negotiable.

## 3. Spacing & layout

- **8pt grid + 4pt half-steps.** Scale: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`.
- Screen edge margin **20–24px** (not 16). Card inner padding 16–20px. Section
  gaps 24–32px.
- Card-based selection. Reader: single column, ~30–40 chars/line.

## 4. Shape

| Token | Radius | Use |
| --- | --- | --- |
| `radius/sm` | 12 | chips, small controls |
| `radius/md` | 16 | inputs, small cards |
| `radius/lg` | 20 | cards |
| `radius/xl` | 24 | sheets, modals |
| `radius/2xl` | 32 | hero panels |
| `radius/pill` | 999 | primary buttons, chips |
| `radius/circle` | 50% | avatars, icon buttons |

**Shadows — soft, COLOR-TINTED, never grey/black:**
- `shadow/sm`: `0 2px 8px rgba(106,137,204,0.10)`
- `shadow/md`: `0 8px 24px rgba(106,137,204,0.12)`
- Night mode: shadows nearly vanish; use lighter surface + faint glow.

**Blob shapes:** decorative organic blobs (`40% 60% 55% 45%`) as background
décor behind headers/illustrations — a genre hallmark. Décor only, not
containers.

## 5. Iconography & illustration

- **Icons:** rounded, filled or thick rounded-stroke (2–2.5px, rounded caps).
  Avoid thin sharp line icons.
- **Illustration is the product's soul.** Duolingo rules for the illustrator:
  basic rounded shapes, fewest shapes, no pointy shapes, bold/bouncy/bright.
  No pure-black outlines — dark navy for line work.

⚠️ **Needs a designer / illustrator (hard flags):**
1. **Mascot / brand character** — commission, don't AI-generate the hero.
2. **In-story illustration style bible** + the product decision: AI-generated
   art per story (scalable, style-inconsistent) vs. fixed illustrated frame /
   character set with generated text.
3. Custom icon set beyond SF Symbols.
4. App icon + onboarding hero art.

## 6. Motion (gentle, slow, wind-down)

- Micro-interactions **150–400ms**; screen transitions **~500ms**, easing
  `cubic-bezier(0.25, 0.1, 0.25, 1)`.
- **Story page-turn:** signature interaction — gentle horizontal slide or soft
  page-curl, ~400–500ms ease-in-out. No bounce in the reader.
- Ambient: very slow drift (stars ~120s cycle) behind the reader.
- Auto-fade reader chrome after ~30s.
- Lottie/Rive for mascot idle, "story is being written" loader, celebration.
- Honor iOS **Reduce Motion** → cross-fades instead of slides.

## 7. Components

- **Buttons:** big, pill, tactile. Primary height 52–56px, full-width CTAs,
  bold 16pt, press-scale 0.97 + tinted shadow. Secondary = soft-tinted pill.
- **Inputs:** `radius/md`, height ≥52px, generous padding, hairline border,
  primary-tinted focus ring.
- **Selection chips/cards (theme picker — core screen):** big tappable cards /
  pill chips with illustration/emoji + label; selected = primary fill/border +
  scale. Multi-select.
- **Story reader:** single column, full-bleed illustration, `story-body` over a
  scrim, page-turn nav, auto-fading chrome, font-size + brightness + night
  toggle, optional TTS play (44px+).
- **Sheets:** bottom sheets, `radius/xl` top corners, drag handle.

## 8. Accessibility (tired parents, at night)

- Tap targets **≥44×44pt**; **night reader controls ≥80px** (used in the dark,
  one-handed, half-asleep). ≥8px between targets.
- Contrast WCAG AA (4.5:1 body, 3:1 large). Test every semantic-on-surface pair;
  soft pastels fail easily. Check accent-on-cream.
- Night reading: low luminance, warm text tones, no bright-white flashes.
- Support iOS Dynamic Type; reader slider supplements it.
- Don't rely on color alone for state.

## Token-file skeleton

`color.{light,dark}.{bg,text,brand,semantic}` · `radius.*` · `space.*` ·
`type.{family,scale}` · `shadow.*` · `motion.{duration,easing}`. Every color
needs light AND dark; every duration/easing named.

## Key sources

- Headspace: Designing for Calm — blakecrosley.com/guides/design/headspace
- Duolingo shape language — blog.duolingo.com/shape-language-duolingos-art-style
- Khan Kids fonts (Fredoka+Linotte) — fontsinuse.com/uses/58074
- Pretendard — noonnu.cc/en/font_page/694 · Gmarket Sans — freekoreanfont.com
- WCAG 2.5.8 target size — w3.org/WAI/WCAG22/Understanding/target-size-minimum
- Pok Pok Playroom — developer.apple.com/news/?id=5bcex7xf
- KR refs: 야나두키즈 kakaokids.com · 째깍악어 (App Store id1189495776)
