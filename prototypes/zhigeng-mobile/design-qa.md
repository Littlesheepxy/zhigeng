# Design QA — 知更 Onboarding Try 页

- Source: `public/reference-option-3.png` (ideate option 3)
- Implementation: `http://127.0.0.1:4173/` idle try state
- Comparison: `design-qa-compare.png`
- Viewport: mobile 390×844 frame

## Iterations

1. First capture: mist asset rendered as hard rectangular photo → P1.
2. Fix: radial mask + larger soft stage; aligned hint copy to source; added status bar.
3. Recapture idle try page and re-compared.

## Findings after fixes

### Accepted product deviations (not defects)

- Progress uses **4** steps (product brief) vs **5** dots in the mock. Visual language of purple capsule + gray dots is preserved.
- Prototype includes working pager pages beyond the single mock frame (brand / keyboard / ready).

### Remaining P3 polish

- Status bar system icons are simplified glyphs, not SF Symbol fidelity.
- Mist texture is a generated soft fog rather than the mock’s exact wave rendering; silhouette and softness now match closely enough for handoff.

## Required fidelity surfaces

| Surface | Result |
|---------|--------|
| Typography | Pass — title/subtitle/hint hierarchy matches |
| Spacing / layout | Pass — robin → title → mic stage → hint → CTA |
| Colors / tokens | Pass — purple mic/CTA, cool mist, white canvas |
| Image quality | Pass after mist mask |
| Copy / content | Pass — 先试一句 / 用你的声音记录想法 / 今天天气怎么样？ / 点一下开始 |

## Interaction check

- Mic / CTA: idle → listening → processing → done compose card → continue unlocks next step
- Progress dots navigate unlocked pages; swipe supported

## final result: passed
