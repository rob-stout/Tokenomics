# Widget Bug Fix Spec
**File:** `TokenomicsWidgets/TokenomicsWidgetEntryView.swift`
**Priority order:** Bug 3 (Large widget cutoff) → Bug 1 (Small icon overlap) → Bug 2 (Small ring overflow) → Bug 4 (Medium deep link) → Bug 5 (Style pass)

---

## Bug 1 — Small Widget: Provider icon overlaps outer ring

### Problem
The `ZStack(alignment: .topLeading)` places the icon and the ring stack as siblings. The icon sits at `.padding(.top, 14).padding(.leading, 14)`, which puts its center at approximately (23.5, 23.5) in widget-local coordinates. The outer ring is 114pt wide, centered in the full widget frame. On the macOS small widget (~169pt wide), the ring's left edge lands at roughly (169/2 - 57) = ~27.5pt. The icon at 19pt wide spans from 14pt to 33pt. The ring edge at ~27.5pt falls directly inside the icon's footprint. They collide.

Additionally, the ring VStack has `.padding(.top, 19)`, which pushes the ring downward but does nothing to prevent the horizontal overlap with the icon.

### Fix
Move the icon out of the ZStack sibship with the ring content and instead compose it as a true overlay pinned to the corner, after the rings have been laid out. Two approaches — use Approach A:

**Approach A (preferred): overlay modifier**

Replace the entire `ZStack(alignment: .topLeading)` with a plain `ZStack` containing only the ring+label VStack, then apply the icon as an `.overlay(alignment: .topLeading)`.

```
ZStack {
    // Ring stack + label
    VStack(spacing: 0) {
        ZStack {
            // ... all ring and percentage content, unchanged ...
        }
        Spacer(minLength: 0)
        Text("Resets in \(provider.shortWindow.shortTimeUntilReset)")
            .font(.system(size: 8.7))
            .foregroundStyle(theme.labelColor)
            .padding(.bottom, 12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.top, 19)
}
.overlay(alignment: .topLeading) {
    providerIcon(provider.id, theme: theme)
        .resizable()
        .scaledToFit()
        .frame(width: 19, height: 19)
        .padding(.top, 14)
        .padding(.leading, 14)
}
```

This ensures the icon always renders above the ring content in Z-order without participating in the ring VStack's layout, and SwiftUI will never push them into the same layout pass that could create measurement conflicts.

**Approach B (minimal diff):** Keep the ZStack but reduce the outer ring diameter (see Bug 2). This is less clean — treat as a last resort.

### Before
`ZStack(alignment: .topLeading)` with icon and ring-VStack as siblings. Icon at (14,14) padding, ring centered in full frame — left edge of ring clips into icon.

### After
`ZStack` with ring content only. Icon pinned via `.overlay(alignment: .topLeading)` at `.padding(.top, 14).padding(.leading, 14)`. No layout collision possible.

---

## Bug 2 — Small Widget: Ring size causes overflow into text areas

### Problem
The outer ring is 114pt diameter with 12pt line width, meaning the full stroke extent (including half the stroke extending outward) is 114 + 6 = 120pt. The small macOS widget content area is approximately 155 × 155pt (after containerBackground insets). With `.padding(.top, 19)` on the VStack, the ring stack's top is at 19pt. The ring occupies 114pt, reaching down to 133pt. The "Resets in..." text has `.padding(.bottom, 12)`, meaning it needs ~20pt at the bottom (8.7pt font ≈ ~11pt line height + 12pt padding). That requires the spacer between ring and text to absorb (155 - 19 - 114 - 23) = ~-1pt — meaning at minimum widget sizes the ring is already touching or overlapping the text.

The tracker dot also extends 6pt beyond the ring's path (dot is 12pt, offset by `radius`), which is the ring's center radius — so the dot clips outside the 114pt frame.

### Fix
Reduce outer ring diameter from 114pt to 104pt. Reduce inner ring diameter from 85pt to 78pt. Keep line widths at 12pt. Update tracker dot radius calculations accordingly.

| Element | Current | New |
|---|---|---|
| Outer ring frame | 114 × 114 | 104 × 104 |
| Outer ring tracker dot radius | 57 | 52 |
| Inner ring frame | 85 × 85 | 78 × 78 |
| Inner ring tracker dot radius | 42.5 | 39 |
| Line widths | 12 | 12 (unchanged) |

The 10pt reduction on outer diameter gives the spacer ~10pt of additional breathing room between rings and the reset text. The proportional reduction on the inner ring maintains the current ~29pt gap between ring centers (outer center r=52, inner center r=39 — gap of 13pt between the ring strokes, same visual weight).

Changes in `SmallWidgetView.body`:

```swift
// Outer ring track
Circle()
    .stroke(theme.barTrack, lineWidth: 12)
    .frame(width: 104, height: 104)

// Outer ring fill
Circle()
    .trim(from: 0, to: min(provider.shortWindow.utilization / 100.0, 1.0))
    .stroke(..., style: StrokeStyle(lineWidth: 12, lineCap: .round))
    .rotationEffect(.degrees(-90))
    .frame(width: 104, height: 104)

// Outer tracker dot — radius 52
.offset(trackerDotOffset(progress: provider.shortWindow.pace, radius: 52))

// Inner ring track
Circle()
    .stroke(theme.barTrack, lineWidth: 12)
    .frame(width: 78, height: 78)

// Inner ring fill
Circle()
    .trim(from: 0, to: min(longWindow.utilization / 100.0, 1.0))
    .stroke(..., style: StrokeStyle(lineWidth: 12, lineCap: .round))
    .rotationEffect(.degrees(-90))
    .frame(width: 78, height: 78)

// Inner tracker dot — radius 39
.offset(trackerDotOffset(progress: longWindow.pace, radius: 39))
```

### Before
Outer: 114pt frame / 57pt dot radius. Inner: 85pt frame / 42.5pt dot radius. Ring bottom edge at ~133pt, leaving ~1pt or less for text breathing room.

### After
Outer: 104pt frame / 52pt dot radius. Inner: 78pt frame / 39pt dot radius. Ring bottom edge at ~123pt, leaving ~11pt for spacer before the reset text.

---

## Bug 3 — Large Widget: 4 providers cuts off content

### Problem (highest priority)
`LargeWidgetView` uses `LargeProviderRow` (spacious layout with header line + two separate bar rows, spacing 12pt inside each row + 8pt between bars) when `providers.count < 5`. Each `LargeProviderRow` has approximately:

- Header HStack: ~17pt (icon height)
- VStack spacing below header: 12pt
- Bar row 1: label (9pt) + bar (4pt) + 2pt spacing = ~13pt total
- Spacing between bar rows: 8pt
- Bar row 2: ~13pt total
- Total per row: 17 + 12 + 13 + 8 + 13 = ~63pt

With 4 providers at 20pt gap between rows:
- Content height: (4 × 63) + (3 × 20) = 252 + 60 = 312pt
- Plus header (~17pt) + header bottom padding (20pt) + top/bottom widget padding (14+14=28pt) = 65pt
- Total: 312 + 65 = 377pt

macOS large widget content area is approximately 342pt tall. 377pt overflows by ~35pt, which matches "Completi..." being cut at the bottom of the screenshot.

### Fix
Lower the compact layout threshold from `>= 5` to `>= 4`.

In `LargeWidgetView.body`, change:

```swift
// BEFORE
let useCompact = snapshot.providers.count >= 5

// AFTER
let useCompact = snapshot.providers.count >= 4
```

Also update the inline comment on `LargeWidgetView` from:
```swift
/// Full-height widget. 1–4 providers: spacious single-column.
/// 5–7: compact 2-column with fixed 24pt gap.
```
to:
```swift
/// Full-height widget. 1–3 providers: spacious single-column.
/// 4–7: compact rows with fixed 24pt gap.
```

No other changes needed. With `useCompact = true` at 4 providers, the view falls into the `else if useCompact` branch (5–7 providers path) using `CompactProviderRow` with 24pt spacing. Each compact row is approximately 17pt tall, so 4 rows at 24pt gap = (4 × 17) + (3 × 24) = 68 + 72 = 140pt — well within the available ~342pt, leaving generous breathing room.

Note: `maxVisible` remains 7. No change needed there.

### Before
`useCompact` triggers at `providers.count >= 5`. 4 providers use `LargeProviderRow` (spacious), overflowing ~35pt and clipping the last row.

### After
`useCompact` triggers at `providers.count >= 4`. 4 providers use `CompactProviderRow` with 24pt spacing, fitting comfortably with room to spare.

---

## Bug 4 — Medium Widget: "+x in app" tap behavior

### Problem
The `+1 in app` (or `+N in app`) footer text in `MediumWidgetView` uses `.widgetURL(URL(string: "tokenomics://open"))` on the entire widget. This is a widget-level URL, so tapping anywhere on the widget — not just the footer — fires it. The `handleGetURL` handler in `TokenomicsApp.swift` has no case for the "open" host (only "share" is handled), so the tap does nothing except bring the app to the foreground. There is no popup.

**Constraint to understand before implementing:** Widget deep links on macOS cannot open a native popover or sheet from within the widget. The widget tap fires a URL, the app process receives it via `NSAppleEventManager`, and the app can respond by opening its own popover (the `MenuBarExtra` window). There is no mechanism to display a widget-internal overlay — that's not how WidgetKit works on macOS.

**Recommended behavior:** Tapping "+N in app" (or anywhere on the widget when overflow is present) should open the app's popover (the menu bar extra window) to show the full provider list.

### Fix

**Step 1 — TokenomicsApp.swift:** Add an "open" case to `handleGetURL`:

```swift
switch url.host {
case "share":
    showShareSheet()
case "open":
    openPopover()
default:
    break
}
```

Add `openPopover()` to `AppDelegate`:

```swift
private func openPopover() {
    // Activate the app so the menu bar extra window comes to front.
    // NSApp.activate brings focus; the MenuBarExtra window visibility
    // is controlled by the system — we can't imperatively .open() it,
    // but activating the app is sufficient for the user to see it.
    NSApp.activate(ignoringOtherApps: true)
}
```

Note: On macOS, `MenuBarExtra` windows are system-managed. You cannot programmatically force them open. `NSApp.activate(ignoringOtherApps: true)` brings the app to the foreground; the user then clicks the menu bar icon to see the popover. This is the correct, HIG-compliant behavior for a menu bar agent.

If you want to attempt programmatic open (not guaranteed by Apple APIs), you can post a custom `NSNotification` that `PopoverView` listens for and use AppKit to find and activate the status item window — but that is fragile and not recommended. The activate-only approach is the right call here.

**Step 2 — Update the footer label copy** to set accurate expectations. "in app" implies it opens something in the app. Since it opens the app (menu bar), this is accurate. No copy change needed.

**Step 3 — Consider making the footer a `Link` instead of relying on widgetURL**, so only the footer tap fires the URL rather than the full widget:

```swift
// Replace the Text with a Link so the tap target is scoped to just the footer
Link(destination: URL(string: "tokenomics://open")!) {
    Text("+\(overflowCount) in app")
        .font(.caption2)
        .foregroundStyle(theme.labelColor)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 10)
}
```

If using a `Link` for the footer, remove `.widgetURL(URL(string: "tokenomics://open"))` from the `VStack` so the rest of the widget doesn't also fire on tap. This is a meaningful UX improvement: tapping a provider row does nothing (no URL fire), tapping the overflow footer opens the app.

**Note on widgetURL:** Currently `.widgetURL(URL(string: "tokenomics://open"))` is on the entire medium widget VStack. This means tapping anywhere on the medium widget fires the URL. That's either intentional (whole widget is a tap target) or incidental. Clarify intent: if the whole widget should open the app, keep `.widgetURL` and just fix the handler. If only specific elements should be tappable, use `Link` on those elements and remove `.widgetURL`.

### Before
`tokenomics://open` URL fires but `AppDelegate.handleGetURL` has no `case "open"` handler — falls through to `default: break`. Tap does nothing beyond app activation.

### After
`case "open"` calls `openPopover()` which activates the app. User can then interact with the menu bar popover.

---

## Bug 5 — General styling observations from screenshot

### 5a. Large widget — header label alignment
In the screenshot, the "Tokenomics" label in the large widget header appears slightly dim but consistent. No issue. The timer "31 sec" is visually correct. No change needed.

### 5b. Large widget — "Completi..." truncation
This is a symptom of Bug 3 (content overflow). Fixing Bug 3 resolves this.

### 5c. Medium widget — compact row label truncation
In the screenshot, the medium widget's compact rows show "5-Hour", "5-Hour", "Tokens" labels — these appear to be truncating to fit the 17pt icon + HStack. The `CompactProviderRow` does not set a `lineLimit` or `truncationMode` on the label text. This is fine; system truncation handles it. No change needed.

### 5d. Small widget — "Resets in 2h 20m" positioning
Currently the text has `.padding(.bottom, 12)`, anchoring it to the widget bottom. This looks correct in the screenshot. After the ring size reduction in Bug 2, there will be more breathing room — the text may appear to float slightly. If it feels visually disconnected after Bug 2 is applied, reduce bottom padding from 12pt to 10pt to keep the text closer to the widget's safe-area floor. Evaluate after Bug 2 is implemented before making this change.

### 5e. Progress bar pace dot visibility
The pace dot on the progress bars (5pt circle, white fill) may be hard to see on the light theme where the bar fill is also a blue tone. Current `theme.paceDotColor` in `.light` is `Color(red: 14/255, green: 51/255, blue: 77/255)` (dark navy) — this is intentional and correct for contrast. No change needed.

---

## Implementation Order

1. **Bug 3** — One-line change in `LargeWidgetView`. Zero risk. Do this first.
2. **Bug 1** — Refactor `SmallWidgetView` ZStack to overlay pattern. Low risk, contained to one view.
3. **Bug 2** — Update 6 numeric values (ring frames + dot radii) in `SmallWidgetView`. Low risk.
4. **Bug 4** — Add `case "open"` to `AppDelegate.handleGetURL` in `TokenomicsApp.swift`. Evaluate whether to scope the tap target with `Link` vs keep whole-widget `.widgetURL`.
5. **Bug 5d** — Optional padding tweak after seeing Bug 2 in Xcode preview.

All changes are in two files:
- `TokenomicsWidgets/TokenomicsWidgetEntryView.swift` — Bugs 1, 2, 3 (and optionally 4's Link change)
- `Tokenomics/App/TokenomicsApp.swift` — Bug 4
