# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

## Locked decisions

- Selected visual: ideate option 3 (Voice Stage try page).
- Onboarding is a 4-page horizontal pager with top progress dots (product uses 4 steps even if mock showed 5).
- Brand: cool purple/lavender mist, Robin mascot asset `public/robin.png`, recording orange for listening only.
- Core interactive path: try dictation mock → unlock keyboard → ready → home shell.
- Keyboard setup is strictly sequential (1→2→3). Current step only is actionable; steps 1–2 open a settings sheet (real app jumps to System Settings); step 3 focuses the verify field. Completed steps turn green with checkmarks.
- Onboarding pages: Brand → Try (+ learn sheet for「小杨」) → Keyboard → Ready (assets reflect learn/keyboard).
- Brand page lower half uses an interactive proof stage, not feature-card/chip inventory: tabs switch Input / Reply / Execute examples and show before → understood result → factual processing tags.
- Home “免切换会话” is a persistent on/off switch, not a one-shot Start button; card and hero status reflect the switch state.
- The post-onboarding app is not a stub: Home closes the voice→result→learning loop; Activity supports type filters and detail sheets; Lexicon supports add/remove terms; Me shows account, keyboard, sync, device, and privacy states.
