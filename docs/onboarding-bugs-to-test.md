# Onboarding bugs — verification checklist

**App version:** 2.9.0-beta.2 (build 49)
**Branch:** `feat/zero-terminal-onboarding`
**Snapshot:** end of the working session that introduced fixes C / D / E.

Bugs C, D, E are fixed in code and need on-device verification. Bug A still
needs diagnostics. Bug B is environmental (cleanup steps below).

---

## Bug A — First-launch fires keychain / cross-app prompts before guided flow

**Status:** Not fixed; root cause unclear. May be environmental.

**Symptom:** On a fresh macOS user account, the Keychain and "Information from
another app" permission prompts fire before any Tokenomics UI appears. The
guided Welcome → Permissions flow does eventually open, but the user has
already been confronted with raw macOS prompts they have no context for.

**Code reading suggests this shouldn't happen:**

- `MenuBarLabel.onAppear` opens the onboarding window when
  `!hasCompletedOnboarding`, then calls `startPolling()`.
- `UsageViewModel.startPolling()` (line 263) short-circuits when
  `!hasCompletedOnboarding`.
- All `ClaudeCredentialStore.currentToken()` callers (ClaudeProvider.swift
  lines 22, 61) are only reachable via `provider.checkConnection()` →
  through polling → gated.
- Widgets and `WidgetDataStore` don't touch keychain.
- No other startup path touches keychain that audit found.

**Diagnostic steps to capture before fixing:**

1. On a fresh user account, after launch but before clicking anything:
   ```
   defaults read com.robstout.tokenomics hasCompletedOnboarding
   ```
   - Returns `1` → something is wrongly marking onboarding complete on launch.
   - Returns nothing or `0` → gating logic is correct; the prompts come from
     a code path the audit missed.

2. Open `Console.app`, filter by `process:Tokenomics`, then relaunch.
   Look for the first log line that mentions Keychain, `SecItem`, or `TCC`.
   That's the smoking gun for which subsystem is firing the prompt.

3. Worth noting: the macOS Keychain itself is system-wide. If a previous user
   on the same Mac installed Claude Code and authenticated, the token entry
   persists across users — macOS still asks each new user for permission to
   access it. The prompt-without-context is the actual UX issue, not the
   prompt itself.

---

## Bug B — Connector skipped "Checking your Mac" when prereqs were already installed

**Status:** Fixed in this session.

**Symptom:** Picking a CLI-based provider (Gemini / Codex / Copilot / Claude) routed straight to the Sign-in / Install CTA, skipping the "Checking your Mac" interstitial entirely when the relevant binary was already on the user's machine. This happens whenever a Mac has the CLI pre-installed system-wide via Homebrew — including fresh user accounts on a Mac where another user installed any of these tools.

**Original framing was environmental** because the underlying state was technically correct (`.installedNoAuth` is the right ProviderConnectionState). But the UX was inconsistent: a fresh-Mac user saw "Checking your Mac" + install confirms + sign-in; a user with a pre-existing binary skipped straight to sign-in. Different first impressions for the same product.

**Fix:** All four CLI-based connectors now show the DetectStep interstitial *once* before transitioning to `.needsAction`, regardless of whether installation is needed. A new `didStartDetection` flag gates the first-return of `.detecting`; it's reset on `cancel()` and `clearFailure()` so retries replay the intro.

**Files:**
- `Tokenomics/Services/Connectors/GeminiConnector.swift` — `.installedNoAuth/.authExpired` branch
- `Tokenomics/Services/Connectors/CodexConnector.swift` — same branch
- `Tokenomics/Services/Connectors/CopilotConnector.swift` — added `didStartDetection` flag, gated all non-connected branches
- `Tokenomics/Services/Connectors/ClaudeConnector.swift` — added `didStartDetection` flag, gated all non-connected branches

**Verification on any Mac (no cleanup needed):**
1. Pick any of the four providers from the chooser.
2. The first screen should be "Checking your Mac" with all rows showing their actual detection status (✓ Installed or ○ Not installed).
3. After ~1.5 seconds (one poll cycle), the screen transitions to either Install confirm (if something missing) or Sign-in (if all present).
4. Stepper progression: 1 (Checking tools) → 3 (Signing in) for the all-installed case; checkmarks on 1 + 2 when arriving at 3 per Bug C fix.

**Note:** The environmental cleanup recipe (`brew uninstall <cli>`) is no longer required to see "Checking your Mac" — it shows up either way now. The recipe is still useful if you want to specifically test the full install flow on a Mac where things are already present.

---

## Bug C — Stepper highlights step 1 on the Sign in screen

**Status:** Fixed in this session.

**Symptom:** When the connector lands on `.needsAction` ("Sign in with
Google"), the stepper shows step 1 (Checking tools) as the active item.
Should highlight step 3 (Signing in) since detection has already completed
and sign-in is the next user action.

**Root cause:** `ConnectorViewModel.stepperItems` lumped `.detecting` and
`.needsAction` together, both highlighting step 1.

**Fix:** Split the cases. `.needsAction` now marks steps 1 + 2 complete and
step 3 active. See `Tokenomics/ViewModels/ConnectorViewModel.swift:42-50`.

**Verification on fresh Mac:**
1. Reproduce Bug B's scenario (gemini binary present but no auth file) by
   running `brew install gemini-cli` then launching Tokenomics.
2. Pick Gemini in the chooser.
3. Stepper should show: 1 ✓ Checking tools, 2 ✓ Installing tools, 3 ● Signing
   in (active blue dot), 4 ○ Connection check.

---

## Bug D — AppleScript "A unknown token can't go after this..." parser error

**Status:** Fixed in this session.

**Symptom:** Homebrew install fails with the user-facing error
`Setup couldn't finish. A unknown token can't go after this """."` Appeared
on Gemini install and any other provider that triggered Homebrew install
(Codex, Copilot).

**Root cause:** `installHomebrew()` interpolated the shell command directly
into the AppleScript source. Even with backslash + quote escaping, the
construction is brittle — a single missed character produces this macOS
runtime parser error. The "A unknown" grammar is from macOS's own AppleScript
runtime, not our string.

**Fix:** Switched to a temp-file approach. The shell command is written to a
file at `FileManager.default.temporaryDirectory/tokenomics-brew-install-<UUID>.sh`,
chmod'd 755, and the AppleScript source only references the path. AppleScript
source is now structurally static — no shell command interpolation — so this
class of parser error is impossible from this code path.

**File:** `Tokenomics/Services/GuidedInstallRunner.swift:368-441`

**Verification on fresh Mac (no Homebrew installed):**
1. Run Tokenomics, pick Gemini (or Codex / Copilot), click through to the
   Install Homebrew confirm screen.
2. Click "Install Homebrew".
3. macOS should show the native admin auth dialog. Approve, cancel, or
   provide a wrong password — all three should produce the *expected*
   user-facing outcome (install proceeds, install cancelled, or
   "Homebrew installation failed" with a plain reason).
4. The "A unknown token" parser error should never appear again.

---

## Bug E — DetectStep stuck on "Continuing..." after "Try setup again"

**Status:** Fixed in this session.

**Symptom:** After a failed Homebrew install (Bug D before its fix, but
applies to any install failure), clicking "Try setup again" landed on the
DetectStep showing all prereqs as "Not installed" with a disabled
"Continuing..." button. The state machine never advanced to "Install
Homebrew" confirm. Same failure pattern on Copilot's setup flow.

**Root cause:** `ConnectorViewModel.pollingTask` was set once in `start()`
but never reset to nil when the polling loop returned (which happens on
`.failed` and `.connected`). `tappedRecovery()` had a guard
`if pollingTask == nil { start() }` that silently skipped restart because
the property still pointed to a Task that had already finished. The UI
showed `step = .detecting` (set directly) but polling was dead — so
`startPrerequisiteChain()` never ran again, `activePhase` never advanced
to `.confirmingInstall(.homebrew)`, and the screen sat forever.

**Fix:** Added a `restartPolling()` helper that explicitly cancels the
stale task, nils the property, and calls `start()`. Both `tappedRecovery()`
and `tappedPermissionDeniedRecovery()` route through it.

**File:** `Tokenomics/ViewModels/ConnectorViewModel.swift:213-243`

**Verification on fresh Mac:**
1. Force any install failure during onboarding (easiest: cancel the macOS
   admin auth dialog during Homebrew install).
2. Click "Try setup again".
3. Within ~1.5 seconds (one poll cycle), flow should transition from
   DetectStep to the Install Homebrew confirm screen. The DetectStep
   "Continuing..." should appear briefly only.

---

## Bug F — Cursor "Waiting for Cursor to install..." doesn't advance after install + sign-in

**Status:** Likely fixed via Bug E's polling-task lifecycle fix. Needs verification on a fresh Mac.

**Symptom:** After clicking "Open cursor.com" in the Cursor onboarding flow, Safari opens to the Cursor download page. User downloads, installs, and signs in to Cursor. Back in Tokenomics, the screen reads "Waiting for Cursor to install — we'll detect it as soon as it's installed." Clicking "Check now" does nothing visible. The expected behaviour is that the screen should transition to the "Cursor is connected" success state.

**Root-cause hypothesis:** The polling task in `ConnectorViewModel` had already returned on some prior terminal state (most likely from a previous attempt in the same session), so the `1.5s` polling that would catch Cursor's install + sign-in was no longer running. The state machine in `CursorConnector.swift` is correct (it transitions `.waitingForBundle → .connected` once `CursorProvider.checkConnection()` returns `.connected`), but the polling loop wasn't there to observe it. Same root cause as Bug E.

**File:** `Tokenomics/ViewModels/ConnectorViewModel.swift:213-243` (the `restartPolling()` fix).

**Verification on fresh Mac (no Cursor.app installed):**
1. Pick Cursor in chooser → "Install Cursor" confirm → "Open cursor.com" → Safari opens.
2. Download + install Cursor → sign in inside the Cursor app.
3. Switch back to Tokenomics. Within ~1.5 seconds the "Waiting for Cursor to install" screen should auto-transition to "Cursor is connected." No "Check now" click needed.

---

## Bug G — Stuck on "Checking your Mac… / Checking for the Cursor app…" with no recovery

**Status:** Fixed in this session.

**Symptom:** After signing in to Cursor (during the Cursor onboarding flow), the UI was sometimes left on the DetectStep spinner fallback — full-screen spinner with no back, no cancel, no escape. Only way to recover was Cmd+Q the app.

**Root cause:** Two issues stacked:
1. The polling loop had terminated (Bug E) so the connector wasn't observing the state change to `.connected`.
2. The DetectStep spinner fallback had no footer chrome — the checklist mode has `WindowFooter` with a Back link, but the spinner mode lacked it.

**Fix:** Added `WindowFooter` with a Back link + Cancel button to the spinner fallback. Both buttons route to the same `onBack` handler — either affordance recovers the user. Independent of Bug E's polling fix, this means a stuck spinner is now never a dead-end.

**File:** `Tokenomics/Views/Onboarding/Steps/DetectStep.swift:204-237`.

**Verification on fresh Mac:**
1. Reach the spinner fallback state (any flow whose detection items array is empty — Cursor is the main case).
2. Confirm the bottom of the window shows: `← Back` (left) and `Cancel` (right text link).
3. Click either — the onboarding window should route back to the chooser (or close, depending on how it was opened).

---

## Bug H — Cursor connected status only updates after quit-and-relaunch

**Status:** Likely fixed via Bug E's polling-task lifecycle fix. Needs verification.

**Symptom:** During an in-progress onboarding session, Cursor never visibly transitioned to "Cursor is connected" (stuck on the waiting / spinner screens of Bug F / Bug G). But after force-quitting Tokenomics and re-launching, Cursor immediately showed as connected in the popover and the onboarding flow's connected-state screen was reachable.

**Root cause:** Same as Bug E + Bug F. Detection was working all along; the user's session just didn't have a live polling loop to observe the state change. Quitting + relaunching freshly initialised `CursorConnector` with `activePhase = .none`, the first `currentStep()` call hit the no-active-phase path, asked the provider, got `.connected`, and the UI showed the success state immediately. The data was always correct — only the in-session UI was stale.

**Verification:** Same procedure as Bug F. If Bug F's verification passes, Bug H is by definition resolved (they're the same underlying loop bug).

---

## Bug I — Claude onboarding shows "Connected" but popover shows "Session expired"

**Status:** Fixed in this session.

**Symptom:** Onboarding flow ends on the "Anthropic is connected ✓" success screen. But opening the popover and switching to the Claude tab shows "Session expired — re-authenticate in your terminal, then click..." with a Refresh button. Clicking Refresh produces the same error.

**Root cause:** `ClaudeProvider.checkConnection()` at `Tokenomics/Services/ClaudeProvider.swift:22` only checks whether a token *exists* in Keychain, not whether it *works*:

```swift
if case .found = await ClaudeCredentialStore.shared.currentToken() {
    let plan = SettingsService.cachedUsage(for: .claude)?.snapshot.planLabel ?? "Pro"
    return .connected(plan: plan)
}
```

The token is presence-checked but not validated. After the token expires, this still returns `.connected`. The actual usage fetch (`fetchUsage()`) is what hits the 401 and surfaces the "Session expired" error in the popover. So onboarding's green check is technically lying about the connection's validity.

**Why "Refresh" doesn't resolve it:** The 401-retry logic in `fetchUsage()` re-reads the token from Keychain in case Claude Code refreshed it. But Tokenomics doesn't refresh the token itself (Anthropic's OpenClaw policy forbids third-party apps from driving the refresh flow). Only running `claude` in Terminal triggers Claude Code's own refresh. Until the user does that, Refresh keeps returning the same expired token.

**The popover's copy is correct** ("re-authenticate in your terminal, then click Refresh") — the bug is that onboarding didn't catch the problem first.

**Fix:** `ClaudeProvider.checkConnection()` now hits `fetchUsage()` once to confirm the token actually works. On 401 it returns `.authExpired` instead of `.connected`. The result is cached for 5 seconds to keep the connector's 1.5s polling from hammering the API (still responsive — at worst, the user sees the green check ~5s after their Terminal sign-in completes).

**File:** `Tokenomics/Services/ClaudeProvider.swift:21-69`.

**Verification on fresh Mac:**
1. Force an expired-token scenario (easiest: install Tokenomics on a user account that inherits a stale Claude Code keychain entry from another user on the same Mac).
2. Walk through the Claude onboarding to the connection step.
3. Onboarding should NOT show "Anthropic is connected." Instead, it should route to the re-auth path (Pattern B — open Terminal). The stepper should show step 3 as active (after Bug C fix).
4. After running `claude` in Terminal and completing sign-in, the connector should pick up the new token within ~5 seconds and finally reach the green check.

---

## Bug J — Claude plan shows as Free when it should be Max

**Status:** Fixed in this session.

**Symptom:** User is on Anthropic's Max plan. Tokenomics shows the Claude plan label as Free (and/or "Pro" as a fallback).

**Root cause:** Two pieces:

1. **`ClaudeProvider.checkConnection()` line 23** defaults the plan to `"Pro"` when no cached usage exists:
   ```swift
   let plan = SettingsService.cachedUsage(for: .claude)?.snapshot.planLabel ?? "Pro"
   ```
   On a fresh user account or a session with no successful fetch yet, this returns `"Pro"` regardless of what plan the user is actually on.

2. **`UsageData.inferredPlan`** at `Models/UsageData.swift:16-24` derives plan from response *shape*:
   - `extra_usage` field present → Max
   - `seven_day_opus` or `seven_day_sonnet` present → Pro
   - Otherwise → Free

   When `fetchUsage()` fails with a 401 (Bug I), no response data → no shape signal → plan-relevant UI elsewhere may default to Free.

**Why Max users are most affected:** Max users are the most likely to see `.connected` (token exists) + `fetchUsage()` failure (expired token) + plan fallback (Pro or Free). Pro / Free users see the same bug but it happens to match their actual plan more often.

**Fix (paired with Bug I):**
- Removed the `?? "Pro"` fallback in `ClaudeProvider.checkConnection()`. The plan label now always comes from a real `fetchUsage()` response in the success path, or is an empty string in the transient-failure fallback path.
- Because Bug I now correctly returns `.authExpired` instead of `.connected` on a 401, the plan fallback is never reached in the broken state — Max users with an expired token see the re-auth flow, not a wrong plan label.

**File:** `Tokenomics/Services/ClaudeProvider.swift:21-69`.

**Verification:** Same as Bug I. After a real successful sign-in, the plan label in the popover should accurately reflect Free / Pro / Max based on Anthropic's response shape (which is what `UsageData.inferredPlan` was already correctly inferring — the bug was that we never got to that inference when checkConnection short-circuited).

---

## Bug K — "Learn more →" on Welcome went to home page instead of privacy policy

**Status:** Fixed in this session.

**Symptom:** The "Learn more →" link in the privacy disclosure on the Welcome screen routed to `https://trytokenomics.com` (the marketing home page) instead of the privacy policy.

**Fix:** Pointed it at the GitHub-hosted `PRIVACY.md` — the same URL `AboutView` uses (`https://github.com/rob-stout/Tokenomics/blob/main/docs/PRIVACY.md`), so the app's two privacy-policy references stay consistent.

**File:** `Tokenomics/Views/Onboarding/WelcomeView.swift:116`.

---

## Bug L — "I'm all set" didn't close the onboarding window

**Status:** Fixed in this session.

**Symptom:** Tapping "I'm all set — show my usage" on the connector's connected screen called `tappedAllSet()` → `onOutcome(.allSet)` → `completeOnboarding()` → `onComplete()`, but the `onComplete` closure passed from `OnboardingWindowRoot` was empty (`{ /* completion handled by VM */ }`). The window stayed open.

**Fix:** Threaded `@Environment(\.dismissWindow)` into `OnboardingWindowRoot` and wired its `onComplete` to:
1. `NSApp.activate(ignoringOtherApps: true)` — brings the menu bar back into focus.
2. `dismissWindow(id: "onboarding")` — closes the window.

**File:** `Tokenomics/App/TokenomicsApp.swift:66-85`.

**Button copy update:** The button was originally "I'm all set — show my usage" — but SwiftUI's `MenuBarExtra` doesn't expose a public API to programmatically *open* its popover (only a real user click on the icon does). Rather than promise behaviour we can't reliably deliver, the button was renamed to "I'm all set." Activating the app gives the Tokenomics icon visual focus; the user clicks it to see usage.

**Verification:**
1. Complete the onboarding for any provider.
2. On the "X is connected" success screen, click "I'm all set."
3. The onboarding window should close. The menu bar Tokenomics icon should be focused — click it to see your usage.

---

## Bug M — API key flow stuck on system spinner after submit

**Status:** Fixed in this session.

**Symptom:** On the Paste API key screen (Pattern E — Stability / Runway / ElevenLabs), tapping "Save & connect" showed the macOS system `ProgressView()` (a small radial swirly) on a dark button, where it's nearly invisible. Worse, if the connection check failed for any reason (bad key, network blip, polling task dead), `isSubmitting` was never reset and the user was stuck looking at a forever-spinner.

**Fix:**
- Replaced `ProgressView().controlSize(.small)` with the project's `CircularSpinner` component, sized 16pt with `Tokens.Color.accentInk(scheme)` so it's legible on the dark primary button.
- Added a 5-second failsafe Task that resets `isSubmitting` to false — if the connector hasn't transitioned us off the paste screen by then, the user can edit + retry instead of sitting on a spinner. On success the parent view re-renders to the connected state and the state is moot.

**File:** `Tokenomics/Views/Onboarding/Steps/APIKeyPasteStep.swift:69-92, 134-150`.

**Verification:**
1. Pick Stability / Runway / ElevenLabs in the chooser → walk to the Paste API key step.
2. Paste a wrong / random API key → tap Save & connect.
3. The button shows a small white/blue spinning ring (not a system swirly).
4. After ~5 seconds the spinner stops, button re-enables, user can edit + retry.

---

## Bug N — Back on Paste API key dumped user all the way to chooser

**Status:** Fixed in this session.

**Symptom:** Clicking ← Back on the Paste API key step called the chooser-level back handler — it dumped the user out of the Pattern E sub-flow entirely, losing context. Should have gone one step back to "Get API key" so the user can re-read the instructions or re-open the provider's dashboard.

**Fix:**
- Added `goBackOneStep()` to the `ProviderConnector` protocol (default no-op).
- Implemented in `APIKeyConnector`: `.pasteKey` → `.openProviderSite`.
- Added `tappedBackOneStep()` to `ConnectorViewModel` that delegates to the connector and refreshes state.
- Wired `ConnectorView.swift` so the `.pasteAPIKey` case routes Back to `viewModel.tappedBackOneStep()` instead of the chooser-level `onBack`.

**Files:**
- `Tokenomics/Models/ProviderConnector.swift` — protocol method + default
- `Tokenomics/Services/Connectors/APIKeyConnector.swift` — `goBackOneStep()` implementation
- `Tokenomics/ViewModels/ConnectorViewModel.swift` — `tappedBackOneStep()`
- `Tokenomics/Views/ConnectorView.swift:155-165` — wiring

**Verification:**
1. Pick any API-key provider → click through to Paste API key.
2. Click ← Back.
3. UI returns to the "Get [Provider] API key" confirm screen, NOT the chooser. Stepper goes back from "Paste key" to "Get API key" being active.

---

## Bug O — Paste API key screen's "Lost your key?" helper was misleading

**Status:** Fixed in this session.

**Symptom:** The helper link on the paste screen read "Lost your key? Generate a new one →". This narrows the user's options — many users don't need to *generate* a new key; they just need to re-open the dashboard to copy their existing one or find where it lives.

**Fix:** Reworded to "Need your key? Open [Provider]'s API keys page →". Same URL behind it (the provider's API key management page). Works for both cases — get a fresh key OR re-find an existing one. Provider name is interpolated dynamically.

**File:** `Tokenomics/Views/Onboarding/Steps/APIKeyPasteStep.swift:49-61`.

**Verification:** On the Paste API key screen for any of the three providers, the centered helper line should read "Need your key? Open [Stability AI / Runway / ElevenLabs]'s API keys page →". Click it — opens the same URL as the "Get API key" step's CTA.

---

## Outstanding: API key URL monitoring

**Status:** Not implemented this session. Tracked as a separate routine task.

**Concern (from Rob):** Provider API key URLs occasionally change (provider dashboards get redesigned). Tokenomics ships with hardcoded URLs at `APIKeyConnector.swift:40-51`:

- Stability AI: `https://platform.stability.ai/account/keys`
- Runway: `https://app.runwayml.com/account`
- ElevenLabs: `https://elevenlabs.io/app/settings/api-keys`

A scheduled remote agent (similar to the OpenAI/Google consumer-OAuth monitor we set up earlier) should periodically verify these URLs still resolve and still land on the API keys page. If a provider moves the page, the routine emails Rob with the new URL so the next release can update.

**Suggested cadence:** monthly (matches the OAuth monitor).
**Suggested deliverable:** Same email-via-Gmail pattern. Subject `Tokenomics: Monthly API-key URL check — YYYY-MM`.

**Action:** Create this routine in a follow-up turn once Rob's ready. For now, the URLs are accurate as of this snapshot.

---

## Outstanding: Flow chart for the API key flow

**Status:** Requested by Rob for clarity. Not yet on the FigJam board.

The full Pattern E flow visually:

```
Pick API-key provider in chooser
            ↓
"Checking your Mac" interstitial (~1.5s — empty checklist) [Bug B fix]
            ↓
"Get your [Provider] API key" (ConfirmInstallStep variant)
   [CTA: Open Provider] → opens dashboard URL in default browser
   [Already have one? Skip] → skips to next step
            ↓
"Paste your API key" (APIKeyPasteStep)
   [Save & connect] → APIKeyService.save() + checkConnection
   [← Back]         → returns to "Get API key" (Bug N fix)
   [Need your key? Open dashboard →] → re-opens provider URL (Bug O fix)
            ↓
"[Provider] is connected" success
   [Add another provider] | [I'm all set]
```

Should be added to the FigJam board as its own section so it can be shared and reviewed independently. Adjacent to the existing chooser-first lanes.

---

## More bugs to add

Append below as you find them.
