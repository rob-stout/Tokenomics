# Beta 3 integration plan — consolidating the in-flight work into `v2.9.0-beta.3`

**Goal:** Get every in-flight branch into one notarized pre-release DMG that you can install
and test end-to-end — *without* touching the stable channel (current stable: **v2.8.7**).

**Last beta shipped:** `v2.9.0-beta.2` (build 49), cut off `feat/zero-terminal-onboarding`.
**This beta:** `v2.9.0-beta.3` (build auto-increments to 50), cut off a new integration branch.

---

## How the beta channel works (confirmed from `scripts/distribute-beta.sh`)

```
stable  →  distribute.sh       →  regenerates appcast.xml  →  Sparkle auto-updates everyone
beta    →  distribute-beta.sh  →  NOT in appcast.xml        →  GitHub --prerelease, manual install
```

- Beta version string must be a pre-release (`2.9.0-beta.3`) — the script hard-fails otherwise.
- Build number auto-increments off `appcast.xml` (next = 50). Stays monotonic even though betas
  never enter the appcast.
- Stable users on 2.8.7 never see this build. Testers drag-replace `/Applications/Tokenomics.app`.

---

## What goes into beta.3

| # | Source branch | Delta over base `ff756d7` | Files | Risk |
|---|---|---|---|---|
| 0 | `feat/brand-aggregation-foundation` | **base** — foundation + onboarding stub wiring | BrandId, FeatureFlags, UsageViewModel helpers | landed |
| 1 | `feat/onboarding-detect-plan` | `DetectionService` + `PlanBuilder` (+tests) | 4 files, services only — **touches no views** | low |
| 2 | `feat/onboarding-extension-connector` | `BrowserExtensionConnector` (5.5.D) | 7 files incl. `ConnectorContainer` (+5) | low |
| 3 | **NEW — glue commit (does not exist yet)** | rewire `ConnectorContainer` stubs → real planner | `ConnectorContainer`, `ConnectorViewModel` | **the real work** |
| 4 | `feat/popover-brand-collapse` | brand tabs + Pin Tracker (flag-gated) | 6 files, incl. `PopoverView` | low |
| 5 | `feat/widgets-brand-surfaces` | brand widget layout + picker (5.6.B/C) | 4 files, widget target | low |

**Critical finding:** branches 1, 2, 4, 5 touch **completely disjoint files** — cherry-picking
them onto one branch produces **zero merge conflicts**. The only hand-written work is step 3.

**Why step 3 is mandatory:** `detect-plan` only *adds* `DetectionService`/`PlanBuilder`; it wires
them into nothing. The onboarding flow (`ConnectorContainer`, commit `2bbe54c`) is still running on
**stub data**. Merging the planner branch does not change that. Someone has to author the commit that
makes `ConnectorContainer` call the real planner — and reconcile it with the `ConnectorContainer`
edits that `extension-connector` (step 2) already made. This is ~1–2 hrs of Claude time + your review.

---

## Integration sequence

```
main (v2.8.7 stable)
  │
  └─ feat/brand-aggregation-foundation  (base: foundation + stub onboarding)
        │
        ▼  create  integration/beta-3  off this branch
        │
        ├─ cherry-pick  detect-plan tip       (planner services)        ← conflict-free
        ├─ cherry-pick  extension-connector    (BrowserExtensionConnector)← conflict-free
        ├─ AUTHOR       glue commit            (stub → real planner)     ← net-new, reconcile ConnectorContainer
        ├─ cherry-pick  popover-brand tip      (flag-gated UI)           ← conflict-free
        └─ cherry-pick  widgets-brand tip      (widget surfaces)         ← conflict-free
        │
        ▼  bump project.yml → 2.9.0-beta.3 (both targets) → xcodegen → full test suite → distribute-beta.sh
```

### Step-by-step

1. **Branch.** `git switch -c integration/beta-3 feat/brand-aggregation-foundation`
2. **Cherry-pick the four feature deltas** (each branch is base + exactly one commit):
   ```
   git cherry-pick feat/onboarding-detect-plan
   git cherry-pick feat/onboarding-extension-connector
   git cherry-pick feat/popover-brand-collapse
   git cherry-pick feat/widgets-brand-surfaces
   ```
   Expect no conflicts (verified: disjoint file sets).
3. **Author the glue commit** — wire `ConnectorContainer` to `DetectionService` + `PlanBuilder`,
   replacing the stub data from `2bbe54c`, integrating cleanly with `BrowserExtensionConnector`.
   *This is the only step that is not mechanical.*
4. **Verify.** Run the full Swift suite + the extension `node:test` suite. Each branch shipped its
   own tests — they become the gate:
   - `FeatureFlagsTests`, `DetectionServiceTests`, `PlanBuilderTests`,
     `BrowserExtensionConnectorTests`, `PopoverBrandAggregationTests`, `WidgetBrandLayoutTests`
   - Known-flaky (pre-existing, ignore): 3 `NotificationContentTests`.
5. **Version bump.** Set `CFBundleShortVersionString: "2.9.0-beta.3"` in `project.yml` for **both**
   targets (main app + widgets). Leave `CFBundleVersion` — the script auto-increments to 50.
6. **`xcodegen generate`** (required after version bump).
7. **`./scripts/distribute-beta.sh`** — archives, notarizes, staples, builds + signs + notarizes DMG.
8. **Gatekeeper check:** `spctl -a -t open --context context:primary-signature -v Tokenomics-2.9.0-beta.3.dmg`
9. **Cut the GitHub pre-release** — ⚠️ the script's hint says `--target feat/zero-terminal-onboarding`;
   change it to `integration/beta-3`:
   ```
   gh release create v2.9.0-beta.3 --prerelease --target integration/beta-3 \
     --title "v2.9.0-beta.3 (beta)" --notes "Beta build — manual install only." \
     Tokenomics-2.9.0-beta.3.dmg
   ```

---

## Decisions you need to make before I start

1. **Glue commit ownership.** This is the one piece of genuinely new logic. I can write it, but it's
   the part most worth you watching — the onboarding code is recently-stabilized.
2. **How testers flip the brand-aggregation flag.** It defaults OFF (stable-safe) and there's already a
   `PopoverView` toggle bound to it. Decide: (a) leave it as the existing popover toggle, (b) surface it
   in a more obvious beta/debug spot, or (c) document `defaults write com.robstout.tokenomics
   tokenomics.brandAggregation.enabled -bool true`. Testers can't exercise brand surfaces without this.
3. **Chrome extension in the test loop.** `BrowserExtensionConnector` detects whether the extension is
   installed and reporting. For full onboarding testing, the tester must load the dev build from
   `extension/dist/` at `chrome://extensions`. That's a tester-setup line in the release notes.

---

## Explicitly NOT in beta.3

- **Safari port (Phase 5)** — separate target work, not started.
- **Extension publish (Phase 6)** — lawyer-gated calendar time. *Start the legal review in parallel now*
  if publishing is on the roadmap; no coding compresses it.
- **Gemini reader (Phase 4)** — deferred pending Google's own dashboard.
- **Stable release** — beta.3 is for testing only. Promotion to a stable `2.9.0` is a later decision and
  uses `distribute.sh` (regenerates appcast, auto-updates everyone) with a non-pre-release version string.
