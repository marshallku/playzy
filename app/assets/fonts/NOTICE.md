# Bundled fonts

## Pretendard

- File: `PretendardVariable.ttf`
- License: SIL Open Font License 1.1 (OFL-1.1) — free to bundle and redistribute.
- Source: https://github.com/orioncactus/pretendard
- Copyright © Kil Hyung-jin (길형진).

Full OFL text: https://github.com/orioncactus/pretendard/blob/main/LICENSE

## Gowun Batang — story-reading serif (DESIGN.md §3)

The warm Korean serif used for the story-reading surface (낭독). OFL-1.1 — free
to bundle and redistribute.

- Files: `GowunBatang-Regular.ttf`, `GowunBatang-Bold.ttf`
- License: SIL Open Font License 1.1 (OFL-1.1)
- Source: https://github.com/google/fonts/tree/main/ofl/gowunbatang
- Copyright © Yoon Design Inc. (윤디자인).
- sha256:
  - Regular `466c593e7147412e748af4856d5ad14709b5a860bdf62b9c2546f2c5874e9849`
  - Bold    `dbfcaa646e5831e7478524924f02906f550285a5050699b4e38c9950b3ec4b94`

## Fredoka — brand wordmark (DESIGN.md §3)

The rounded Latin display face used **only** for the "Playzy" wordmark. OFL-1.1.

- File: `Fredoka-Variable.ttf` (variable: width + weight axes)
- License: SIL Open Font License 1.1 (OFL-1.1)
- Source: https://github.com/google/fonts/tree/main/ofl/fredoka
- Copyright © The Fredoka Project Authors (Milena Brandão, Hafontia).
- sha256: `2ba02e68b152868aef9ba28e24b3648c7d457fe6f25c761f2c2c53fb61a73fc8`

> **App-size note:** the two Gowun Batang faces add ~16 MB (full Korean serif
> glyph set). Glyph **subsetting** to the characters actually rendered is a
> tracked size-optimization follow-up (`docs/planning/90-open-decisions.md`).
