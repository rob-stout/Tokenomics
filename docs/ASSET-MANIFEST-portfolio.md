# Tokenomics Case Study — Asset Manifest

Checklist for the visuals in the inline web case study at `/work/tokenomics/`
(`portfolio-site/src/data/case-studies.ts`, the `tokenomics` entry).

The story is **fully readable today**: every image that doesn't exist yet renders as a
**labeled dashed placeholder** showing its description, in place, so you can see exactly what
each slot needs. Drop the real file in and it lights up.

### How wiring works
- **Narrative figures** (the `twoUp` / `figure` blocks): currently have **no `src`**, so they
  show the descriptive placeholder. When you produce the image, save it to the path below and
  add `src: "/tokenomics/<file>"` to that block (a one-line edit — ping me and I'll wire each
  one as the files land).
- **The widget before/after slider** (inside the interactive "Behind the build" section) is
  **already wired** to two paths and falls back to a placeholder panel until they exist. Just
  drop the two files in and the slider shows them — no code change needed.

### Export specs
- **Screenshots / renders → `.avif`** · **diagrams → `.svg`** · export **@2x**.
- The site has **light + dark mode**. Prefer screenshots with a neutral/transparent surround,
  or capture **both modes** where the chrome matters (menu bar, popover).
- Crop to the artifact — no desktop clutter unless the desktop context is the point.
- Match the **aspect** listed so the renderer doesn't crop.
- Destination dir: **`portfolio-site/public/tokenomics/`** (already exists; provider icons +
  menu-bar SVGs are already in it).

---

## Required (the story leans on these)

| Beat | Asset | Save as → `public/tokenomics/` | Aspect | Notes |
|---|---|---|---|---|
| 9 · Widgets card | **Widget "before"** — the AI/early layout with dead white space at the bottom | `widget-before.avif` | ~1/1 | Slider auto-loads. The "AI filled the grid and left empty space" state. If unreconstructable, tell me and we relabel it honestly. |
| 9 · Widgets card | **Widget "after"** — Figma-polished medium widget with the Share CTA earning the space | `widget-after.avif` | ~1/1 | Slider auto-loads. Pair to the above. |
| 7 · twoUp | **Mac popover** — tabbed providers, two rings + pace marker, plan badge, privacy line | `popover-mac.avif` | 3/4 | Left half of the "one design system, two platforms" pair. |
| 7 · twoUp | **Extension popup** — the browser popup, visually identical to the Mac popover | `popover-extension.avif` | 3/4 | Right half. The 1:1-port punchline only lands if these look the same. |
| 2 · twoUp | **Menu-bar glyph, light** — the two-ring icon in the macOS menu bar, light mode | `menu-bar-light-shot.avif` | 4/3 | A real menu-bar screenshot. (Brand SVGs `menu-bar-light.svg`/`-dark.svg` are already here as a fallback if you'd rather use the clean glyph.) |
| 2 · twoUp | **Menu-bar glyph, dark** — same, dark mode | `menu-bar-dark-shot.avif` | 4/3 | Pair to the above. |

## Optional (nice depth; placeholders are fine without them)

| Beat | Asset | Save as | Aspect |
|---|---|---|---|
| 5 · figure | Small + medium + large **widgets on a desktop** | `widgets-gallery.avif` | 16/9 |
| 4 · (add a figure) | **Popover with provider tabs** — Claude/Codex/Gemini/Copilot/Cursor | `popover-tabs.avif` | 16/9 |
| 6 · (add a figure) | **Connections / ecosystem page** — section grouping, "Codex · DALL-E · Sora" subtitle | `connections.avif` | 4/3 |
| 8 · (add a figure) | **Onboarding v1 → v2** — before/after with the new connect-the-extension step | `onboarding-rework.avif` | 16/9 |
| 10 · (add a figure) | **Release pipeline** — terminal mid-run (sign, notarize, cask) | `release-pipeline.avif` | 16/9 |

---

## Already hosted (no action needed)
- **Brand guidelines page** → `/tokenomics-brand/` (HTML + 50 assets). Linked from the Brand card.
- **Guided onboarding mockup** → `/tokenomics-onboarding/` (live click-through). Linked from the Onboarding card.
- **Provider icon set** (11, white variants) → `public/tokenomics/icons/` — used in the Brand card strip.
- **Menu-bar + usage SVGs** → `public/tokenomics/` (`menu-bar-light.svg`, `menu-bar-dark.svg`, `usage-animation.svg`, `menu-animation.svg`).
- **Pace-dot explainer** (Beat 3) and the **before/after slider chrome** (Beat 9) are drawn in code — no asset.

## Confirm before publish (facts move fast)
- **Creative providers** — Midjourney / Suno / Udio live status (trytokenomics.com still says "coming soon"; you said live via the extension). The copy says "the first usage tracker shipped for Midjourney anywhere" — confirm that's still true.
- **Extension status** — shipped vs. beta, and the **~14 providers** total.
- **Version** — copy says **v2.9**; confirm current.
- **"50+ daily users"** — intentionally **omitted** (unverified). Add back only if you want to stand behind it.
