# In-app and in-extension copy updates for launch

Every change below is "current text" vs "proposed text", with the exact file. Nothing was edited; this is a list for implementation. Written 2026-10-27. Paths are relative to `/Users/jarvis/projects/tokenomics-extension-publish/`.

Priority key: **P0** must change before submitting (wrong or contradicts the listing). **P1** should change for launch. **P2** nice to have.

---

## 1. `extension/src/manifest.json` (P0)

| Field | Current | Proposed |
|---|---|---|
| `name` | `Tokenomics` | `Tokenomics: AI Usage & Limits Tracker` (37 of 75) |
| `description` | `Track your AI usage at a glance.` | `See your AI usage and limits at a glance, across the AI sites you pay for. Free, no analytics.` (94 of 132). Brand-free on purpose; the legal guide bars third-party names in the title and short description. |
| `version` | `0.1.0` | `1.0.0` (first public release; the Safari app is 1.0 (1)) |
| `action.default_title` | `Tokenomics` | Keep. It's the hover tooltip; short is better. |
| `key` | long public key | Remove for the store build (the legal agent's plan). The store then assigns its own ID, so the Mac app's allow-list must be updated (see section 8c). Keep the key in dev builds. |

Notes:
- Chrome and Edge show `name` and `description` straight from the manifest unless you add `_locales`. Keep the store fields and the manifest identical so nobody files "listing doesn't match package".
- Safari also reads this manifest. The name and description will appear in Safari Settings > Extensions. That's fine.
- The Safari app display name stays "Tokenomics for Safari" (separate field in `TokenomicsSafari/Info.plist`).

---

## 2. `extension/src/popup/components/EmptyState.tsx` (P1)

The existing copy is mostly good: it already says "sign in" for web providers instead of pushing the Mac app. Three small edits.

**2a. Native-only providers** (Copilot, Cursor, Gemini CLI; line 22)

| Current | Proposed |
|---|---|
| `Tokenomics reads {meta.displayName} from the app on your Mac. Open it to see your usage here.` | `{meta.displayName} is tracked by the Tokenomics Mac app, not the browser. Install the app and it shows up here.` |

Why: the current line assumes the app is installed ("Open it"). A first-time extension user doesn't have it. The CTA below already reads "Open Tokenomics →" (line 30), which links to the website. Change that to `Get the Mac app →` for the same reason.

**2b. ChatGPT counter** (`COUNT_LOCALLY` branch, line 60)

| Current | Proposed |
|---|---|
| `Tokenomics counts your ChatGPT usage as you chat. Open {countLocally.site} and send a message.` | `Open {countLocally.site} and send a message. Tokenomics starts tracking from there.` |

Why: `extension/src/chatgpt.ts` now has a path that reads usage from the site (`estimated: false`, line 145) and a fallback that counts messages (`estimated: true`, line 307). "Counts as you chat" describes only the fallback. Rob: confirm which state triggers this empty state before shipping; if only the fallback, keep the current text.

**2c. Fallback** (last return, line 85)

| Current | Proposed |
|---|---|
| `Track {meta.displayName} in the Tokenomics menu bar app.` | `{meta.displayName} is tracked by the Tokenomics Mac app.` |
| CTA `Install Tokenomics →` | `Get the Mac app →` |

Sign-in empty state (line 40-41, `Tokenomics reads your {name} usage from the web. Sign in to {site} to see it here.`): leave as is.

---

## 3. `extension/src/popup/components/BridgeBanner.tsx` (P1, behaviour decision)

**Current** (line 30-40): a warning-styled banner (`bridge-banner--warn`) reading `Mac app not detected. Install Tokenomics to see menu-bar usage.` It shows on every popup open for anyone without the Mac app.

Problem: at launch most extension users won't have the Mac app, and the extension is meant to work on its own. A permanent warning on a working product reads as "something is wrong" and sends people to download software before they've seen a number.

**Proposed text** (neutral, same position):

> Works on its own. Add the Mac app for menu bar rings and widgets. **Get the Mac app**

Proposed behaviour (code change, small): make it dismissible, remembered in `chrome.storage.local`, and style it as a neutral note rather than a warning. If that's more than you want for launch, change the text and the style class only.

Keep the "connected" chip (`Tokenomics {version}`) and the "connection unstable" caution as they are.

---

## 4. `extension/src/popup/components/NativeFooter.tsx` (no change)

`Tracked by Tokenomics on macOS` is clear. Leave it.

---

## 5. `extension/src/options/options.tsx` (P1 / P2)

**5a. "Tokenomics for Mac" section** (lines 294-305; P2)

| Current | Proposed |
|---|---|
| `See all your usage — including Claude Code, Codex, Copilot, and Cursor — in your menu bar and desktop widgets.` | `See your web usage next to Claude Code, Codex CLI, Gemini CLI, GitHub Copilot and Cursor, in your menu bar and desktop widgets.` |

Why: matches the product names used elsewhere and now says what the Mac app adds to what the extension already shows.

**5b. ChatGPT plan section** (lines 258-262 and the `buildOptions` helpers; P1)

The helper lines state specific limits (`10 messages / 5-hour window`, `160 messages / 3-hour window · 3,000 Thinking messages / week`, `15,000 Thinking messages / week`). `extension/README.md` says these reflect "May 2026 OpenAI defaults" that "shift quarterly". Printing numbers in the UI that can go stale is a trust risk, and the store listing promises honesty about estimates.

| Current (line 258) | Proposed |
|---|---|
| `Override the plan Tokenomics uses to calculate your ChatGPT quotas. Auto-detect reads your plan directly from the ChatGPT session — only override if detection gets it wrong.` | `Override the plan Tokenomics uses to estimate your ChatGPT quotas. Auto-detect reads your plan from your ChatGPT session. Only change it if detection gets it wrong. Limits are estimates and can change when OpenAI changes them.` |

Rob: verify the per-plan numbers in `buildOptions` against OpenAI's current published limits before launch. If you can't, drop the numbers from the helper lines and keep just the plan names.

**5c. Footer: privacy and support links** (P1, new)

Add a small footer to the options page:

> Privacy policy · Help
> (`https://trytokenomics.com/privacy`, `https://trytokenomics.com/faq`)

Why: the Chrome store wants the policy easy to find, and users with a problem need somewhere to go.

**5d. `extension/src/options/index.html`** (no change). `<title>Tokenomics — Settings</title>` is fine.

---

## 6. `extension/README.md` (P0)

This isn't a UI string, but the repo is public and the store reviewers, press and curious users read it. It now contradicts the listing in four places:

| Current text | Problem | Proposed |
|---|---|---|
| `Phase 1.5 + 4.5 ships three providers` (line 6) | The extension reads eight sites. | `The extension reads usage from eight AI sites: Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity and Leonardo.` |
| `Cookies aren't read; tokens aren't extracted.` (line 124) | Not accurate. The ElevenLabs content script reads the site's token and the background worker saves it, and Leonardo's script picks up the page's `Authorization` header and account ID; both are stored unencrypted in `chrome.storage.local`. (Gemini's script does not capture a token; it reads values inside the page and reports only usage numbers. This follows the legal agent's code review in `privacy-policy-update.md`, "Fact-sheet corrections".) The store disclosure says "authentication information"; the README must not contradict it. | `The extension uses your existing signed-in session to ask each site for your own usage numbers. For ElevenLabs and Leonardo it also saves the access token the site gives your browser, unencrypted, in the browser's extension storage so numbers can keep refreshing. Nothing is sent to us.` |
| `host_permissions: [... three providers]` (line 130) | Manifest lists ten host patterns. | Update to the real list in `manifest.json`. |
| `No native messaging bridge to the Mac app — Phase 2.` and `Chrome only. Safari port lands in a later phase.` (lines 153-154) | Both are shipped. `nativeMessaging` is in the manifest, and Safari exists. | `Syncs with the Tokenomics Mac app through native messaging when it is installed. Also ships as a Safari extension in "Tokenomics for Safari".` |

Also: the intro says "No telemetry, no analytics, no remote reporting." Keep it.

---

## 7. `TokenomicsSafari/ContentView.swift` (P1)

| Where | Current | Proposed |
|---|---|---|
| Disabled-state lede (line 49) | `One switch and Tokenomics starts reading your web AI usage — ChatGPT, Gemini, Claude, and more — right in Safari.` | `Turn it on, then allow it on the sites you want it to read. Tokenomics shows your web AI usage — ChatGPT, Gemini, Claude and more — right in Safari.` |
| Enabled state, no heartbeat yet (line 76) | `Waiting for your first visit to a supported site.` | Keep. |
| Funnel (line 89) | `Want menu-bar rings, desktop widgets, and your Claude Code, Codex, Copilot, and Cursor usage too?` | `Want menu bar rings, desktop widgets, and your Claude Code, Codex CLI, Gemini CLI, Copilot and Cursor usage too?` |
| Funnel button (line 94) | `Get the full Tokenomics app for Mac →` | Keep, **but** see the App Review note in `app-store-listing-safari.md` section 3. If review objects, change to `Learn about Tokenomics for Mac →` and link to `https://trytokenomics.com/extension`. |

Why the first row changes: Safari makes users approve each site. "One switch" under-promises that step, and a user who flips the switch and sees nothing will think it's broken. The review notes and the App Store description both mention the per-site step, so the app should too.

I did not verify on a device exactly how Safari words its per-site prompt for this extension's host permissions. Test once on your Mac and adjust the line to match what you see.

---

## 8. `Tokenomics/Services/Connectors/BrowserExtensionConnector.swift` (P0)

**8a. Footnote is inaccurate** (line 130; P0)

| Current | Proposed |
|---|---|
| `The extension reads only your usage counts — never your prompts, messages, or files. It runs locally and talks only to Tokenomics on your Mac.` | `The extension reads your usage numbers, not your prompts, messages, or files. It talks to the AI sites you use and to Tokenomics on your Mac, and nowhere else.` |

Why: the current sentence says it "talks only to Tokenomics on your Mac". It also calls the AI sites. A privacy sentence that's wrong, shown at the moment of install, is the most expensive kind of copy error. `BrowserExtensionConnectorTests.swift` may assert on the footnote; update the tests with it.

**8b. Store URLs** (lines 104 and 118; P0, **[WAITS: URLs]**)

| Constant | Current | Proposed |
|---|---|---|
| `webStoreURL` | `https://chromewebstore.google.com/detail/gcjaebikgcbccgbnbcimccflcgoeefio` | Confirm it resolves to the live listing. If the store assigns a different ID, update this and the allowed origin in `NMHManifestInstaller.swift` (line 23) together. |
| `appStoreURL` | `https://trytokenomics.com` with a TODO (lines 114-118) | The real `https://apps.apple.com/app/tokenomics-for-safari/id<ID>` URL. Remove the TODO. This constant also drives `AboutView.swift:92` and `PopoverView.swift:801`. |

**8c. Extension ID in the Mac app** (P0 if IDs differ)

`Tokenomics/Services/NMHManifestInstaller.swift` line 23 allows only `chrome-extension://gcjaebikgcbccgbnbcimccflcgoeefio/`. With the dev `key` removed for the store build, the Chrome store ID and the Edge Add-ons ID will both be different, and Mac sync fails silently for store users. Add both real IDs (keep the dev one for development builds) to `allowedOrigins` and ship a Mac update **before** the extension goes public. Test with an Unlisted upload first. Same conclusion as `legal/edge-addons-notes.md` section 1.

**8d. Edge users** (P2)

`WorkspaceDefaultBrowserDetector` only checks for Safari; everyone else gets the Chrome Web Store button. An Edge user lands on the Chrome store. That works (Edge can install from it), but the label `Open Chrome Web Store` is slightly off for them. Low priority; consider `Get the extension` as a neutral label if you add an Edge branch later. `BrowserExtensionConnectorTests.swift:351` asserts the current label.

**8e. Install-step body copy** (lines 153 and 164; no change)

`Tokenomics reads your web usage — ChatGPT, Gemini, and more — ...` is good as is.

---

## 9. Mac app Settings: add a Chrome row (P2)

`Tokenomics/Views/PopoverView.swift` lines 794-802 show a "Browser" section with only `Tokenomics for Safari` and the subtitle `Track your web AI usage in Safari.` Chrome and Edge users have no link.

Proposed: add a second row.

| | Label | Subtitle | URL |
|---|---|---|---|
| Existing | `Tokenomics for Safari` | `Track your web AI usage in Safari.` | `BrowserExtensionConnector.appStoreURL` |
| New | `Tokenomics for Chrome and Edge` | `Track your web AI usage in Chrome or Edge.` | the Chrome store URL, exposed like `appStoreURL` |

`AboutView.swift` lines 89-93 have the same single link; leave it.

---

## 10. "Open source" in the Mac app (P0, claims fix)

`Tokenomics/App/TokenomicsApp.swift` line 218:

| Current | Proposed |
|---|---|
| `Tokenomics — see your AI coding tool usage at a glance. Free and open source.` | `Tokenomics — see your AI usage at a glance. Free, with source available on GitHub.` |

Why: the license is source-available, and the legal guide (`trademark-and-claims-guide.md` section 6) says to stop using "open source" anywhere public. The same words appear in `linkedin-post.md` (line 19, a draft). The legal agent mentions the Mac app's About text too; my search for "open source" in the Swift files found only the share text, so check `AboutView.swift` for a differently spelled version. I also dropped "coding tool" because the app now covers more than coding tools once the extension is paired. Rob: revert that part if you want the share line to stay coding-focused.

---

## 11. First-run consent screen (P0 if Rob builds it; the legal agent recommends it)

Source text and reasoning: `docs/publishing/legal/chrome-web-store-privacy-practices.md` section 6. It is user-facing copy, so I read it for voice. It is plain, short and honest (it says outright that stored tokens aren't encrypted). I would not soften it.

Marketing consequences if it ships:
- The popup's very first state is the consent text with `Agree and turn on` / `No thanks`. The empty states in section 2 only appear after consent.
- Store screenshots are taken after consent.
- Reviewer test steps get a "click Agree" line (already added in the Chrome and App Store drafts as an optional step).
- Safari: the same text goes in the `TokenomicsSafari` window before "Open Safari Extensions…" (`ContentView.swift`, `disabledContent`). That means the "Turn on Tokenomics in Safari" screen gets a step before it.
- The site's `/extension` and FAQ must say the same things in the same words on stored tokens (their check list says a mismatch is a common rejection reason).

One wording tweak I'd suggest, pending Rob's call: the disclosure's title `Before Tokenomics starts` is fine. The buttons `Agree and turn on` / `No thanks` are fine. Leave both.

---

## 12. Items I checked and left alone

- `extension/src/popup/index.html` title `Tokenomics`: fine.
- `extension/src/popup/components/SyncFooter.tsx` strings (`Not yet synced`, `Updated just now`, `Updated {n}m ago`): fine.
- `TokenomicsSafari/Info.plist` display name and category: correct for the App Store record.
- Site `app.js` / `index.html` version pill (`v2.9.0 · macOS 14+`) looks out of date next to the current release (2.9.3 per recent commits). It's a `js-version` element so `app.js` may refresh it at runtime; if not, bump it. Separate from this launch.
