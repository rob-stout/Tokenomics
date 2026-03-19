# macOS WidgetKit Widget Sizes

> Measured on macOS Sequoia. Tested on both a 14" MacBook Pro and a 27" Apple Studio Display — dimensions are **identical on both**, confirming macOS uses fixed widget sizes regardless of display size or resolution.
>
> Measured by Rob Stout using Tokenomics (macOS menu bar app).

---

## Dimensions at a Glance

| Size   | Outer Frame       | Content Area (est.) |
|--------|-------------------|----------------------|
| Small  | 164 × 164 pt      | ~128 × 128 pt        |
| Medium | 344 × 164 pt      | ~308 × 128 pt        |
| Large  | 344 × 344 pt      | ~308 × 308 pt        |

Content area is inside the automatic `.containerBackground` padding (~18pt inset on each side). These are estimated from the proportional reduction observed — Apple does not expose the exact inset value.

---

## The Core Finding: Sizes Are Fixed

Apple does not publish widget point dimensions anywhere in the HIG, developer documentation, or SwiftUI API. The only way to get ground truth is to measure.

Key behavior:

- Widget frames are **the same size on every Mac**, from an M2 MacBook Air to a Mac Pro on a Studio Display
- Text does **not** scale with display size — a 10pt label is 10pt everywhere
- Retina displays render at **2× pixel density**, so 164pt = 328px on a Retina screen, but the point size is fixed
- macOS does not do display-adaptive sizing the way iOS does (iOS widgets vary by device screen class)

---

## Proportional Relationships

These aren't arbitrary numbers — the sizes follow a grid:

```
Medium width  = Small width  + gap + Small width  →  164 + 16 + 164 = 344 pt
Large height  = Small height + gap + Small height  →  164 + 16 + 164 = 344 pt
Large width   = Medium width                        →  344 pt
```

The **16pt gap** is the inter-widget spacing macOS uses when widgets sit adjacent on the desktop. Small, Medium, and Large all snap to this grid, which means a 2×2 arrangement of Small widgets occupies exactly the same footprint as one Large widget.

---

## Working With These Dimensions

### In Figma
- Use **1× (point) values** directly — 164, 344, etc.
- Figma handles @2x export separately; don't double the values
- Corner radius: **22pt** matches macOS widget corners
- Inter-widget gap: **16pt**

### In HTML / CSS mocks
- CSS `px` maps 1:1 to macOS points on Retina displays
- `width: 164px` in CSS = 164pt = 328 physical pixels on a 2× Retina display
- This is correct and intentional — don't compensate for pixel density in CSS

### In SwiftUI
- Don't hardcode these values. Use `widgetFamily` + `containerBackground` and let the system size the widget
- These measurements are useful for design work, not for `frame()` calls in widget code

---

## Why Apple Doesn't Publish This

Likely intentional — Apple reserves the right to change widget sizes across macOS releases without breaking documented API contracts. Widgets are sized by the system, not the developer. The practical implication: treat these as **current ground truth for Sequoia**, not permanent spec.

---

## Quick Reference Card

```
macOS Sequoia Widget Sizes (points)
────────────────────────────────────
Small   164 × 164   content ~128 × 128
Medium  344 × 164   content ~308 × 128
Large   344 × 344   content ~308 × 308

Inter-widget gap: 16pt
Corner radius:    22pt
Pixel density:    2× (Retina)  →  pt × 2 = physical px

Same on all displays. No adaptive sizing.
```
