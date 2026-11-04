# App Store Connect listing: Tokenomics for Safari

Platform: macOS. Bundle display name: "Tokenomics for Safari" (fixed; the App Store record already exists). Build 1.0 (1) is already uploaded. Counts done by hand; re-check with `pbpaste | wc -m`. Written 2026-10-27.

---

## 1. Fields

### Name

`Tokenomics for Safari` (21 of 30). Already set. Don't change.

### Subtitle (30 max)

```
AI usage & limits at a glance
```

Count: 29.

The name already carries "Safari", so the subtitle spends its words on what the app does and on search terms ("AI", "usage", "limits"). Don't repeat these in the keyword field.

### Promotional text (170 max, editable any time without a new build)

```
See how much of your AI limits you've used, right in Safari. Turn it on once, then check before you start a long chat or a big render.
```

Count: 134 of 170.

### Description (4,000 max)

Count: about 3,200. Plain text. The first three lines show before "more", so they carry the whole pitch.

```
Tokenomics shows how much of your AI limits you've used, right in Safari. Click the toolbar icon to see what you've used, when it resets, and whether you're going too fast.

Turn it on once. Then it just sits in your toolbar.

WORKS WITH
Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity and Leonardo. Sign in to a site the way you normally do, and its meter appears in the popup. Safari asks you to allow Tokenomics on each site, so you choose which ones it can read.

WHAT YOU GET
• One popup, one tab per site
• Usage bars with a pace marker. If your bar is ahead of the marker, you're using your allowance faster than an even pace.
• Reset times, so you know when you're back
• A toolbar badge showing the site you're closest to running out on
• Hide the sites you don't use

HONEST ABOUT NUMBERS
Tokenomics shows the usage numbers each site reports. Some sites only allow estimates. When a reading is an estimate, the popup says so. Numbers refresh every few minutes.

PRIVACY
• No analytics. No telemetry. No account to create.
• Tokenomics sends nothing to us. It talks only to the AI sites you use, with the sign-in you already have, and to the Mac app on your own computer if you have it.
• It saves your settings and usage numbers on your Mac, in Safari's extension storage. It does not store your prompts or conversations.

GO FURTHER WITH THE MAC APP (OPTIONAL)
This app works on its own. If you also install the free Tokenomics app for Mac from trytokenomics.com, they sync. Your web usage then shows up in the menu bar and in desktop widgets, next to Claude Code, Codex CLI, Gemini CLI, GitHub Copilot and Cursor.

FREE
Tokenomics for Safari is free. No subscription, no ads, no in-app purchases.

HOW TO TURN IT ON
1. Open Tokenomics for Safari.
2. Click "Open Safari Extensions…" and switch Tokenomics on.
3. Allow it on the sites you want it to read.
4. Visit a supported site and click the Tokenomics icon in the Safari toolbar.

Need help? https://trytokenomics.com/faq

Tokenomics is an independent tool and is not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, Google, Midjourney, ElevenLabs, xAI, Perplexity, Leonardo.Ai, or any other AI service it works with. Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity, Leonardo, and all related names and marks are the property of their respective owners and are used here only to identify the services Tokenomics works with.
```

(Disclaimer is the verbatim standard text from `docs/publishing/legal/trademark-and-claims-guide.md` section 3. Apple Guideline 5.2 applies; brand names stay out of the name, subtitle, keywords and promotional text.)

The description is about 3,200 characters, so it is inside the 4,000 limit, but the disclaimer takes a lot of it. Don't add more.

Checks:
- "Sign in... its meter appears": true per the popup empty-state logic.
- "Safari asks you to allow Tokenomics on each site": that is how Safari web extensions work, but confirm on your own machine that the per-site prompt appears for the host permissions in this manifest. Open question if it doesn't.
- "no in-app purchases": confirmed by the Info.plist/app having none; verify nothing in the project adds StoreKit.
- "Open Safari Extensions…" matches the button label in `TokenomicsSafari/ContentView.swift`.

### Keywords (100 max, comma-separated, no spaces)

```
quota,tracker,monitor,meter,credits,tokens,LLM,chatbot,generative,rate,dashboard,toolbar,rings
```

Count: 94.

Rules I followed:
- No words already in the name or subtitle (Tokenomics, Safari, AI, usage, limits, glance).
- No competitor or third-party trademarks (no Claude, ChatGPT, Gemini, Midjourney and so on). Apple rejects metadata that leans on other companies' marks.
- Singular forms; Apple matches plurals.
- "rings" is a deliberate bet for people who've seen the Mac menu bar rings. It's the weakest word. Swap it for `reset` if you want a safer pick.

### URLs

| Field | Value |
|---|---|
| Support URL | `https://trytokenomics.com/faq` |
| Marketing URL | `https://trytokenomics.com/extension` (use `https://trytokenomics.com` until that page is live) |
| Privacy Policy URL | `https://trytokenomics.com/privacy` |

### Category

| | |
|---|---|
| Primary | Utilities (matches `LSApplicationCategoryType` = `public.app-category.utilities` in `TokenomicsSafari/Info.plist`) |
| Secondary | Productivity |

### Copyright

```
2026 Acorn Designs, LLC
```

Matches the site footer and the legal agent's note (`app-store-privacy-label.md`). Apple's format is "year, then owner name", so no © symbol or URL in the field. Confirm the developer account is an organization account for Acorn Designs, LLC, not Rob personally.

### Age rating, privacy label, export compliance

Use the legal agent's answers: `docs/publishing/legal/app-store-privacy-label.md`.

- App Privacy: **Data Not Collected** (their section 1). The label, the policy and the description must say the same thing.
- Age rating: expected 4+ (their section 3).
- Export compliance: set `ITSAppUsesNonExemptEncryption` = `NO` in the Safari app and extension Info.plists so the question stops appearing on each upload (their section 2). I confirmed `TokenomicsSafari/Info.plist` doesn't have it today.
- Price: Free. Availability: all regions you're comfortable supporting; English-only listing at launch.
- EU trader status (DSA): decide deliberately; it shows contact details publicly (their section 1, last bullets).

### What's New in 1.0

```
First release. Turn on Tokenomics in Safari and see your AI usage and limits at a glance: reset times, a pace marker, and a toolbar badge for the site you're closest to running out on. Works on its own, or sync with the free Tokenomics Mac app for menu bar rings and widgets.
```

Count: about 290 (limit 4,000).

---

## 2. Mac screenshot plan

Required: at least 1, up to 10. Apple accepts Mac screenshots at 1280×800, 1440×900, 2560×1600 or 2880×1800 (16:10). Make them at **2880×1800** and Apple scales down. PNG or JPEG, no alpha.

Common treatment: a clean Mac desktop in light mode with the default wallpaper blurred, Safari window with no personal tabs, made-up numbers. Caption set at top in the site's serif with one italic accent word, over a flat cream or navy band. Same style as the Chrome shots so the two stores feel like one product.

| # | Shows | Caption |
|---|---|---|
| 1 | Safari window on a neutral page. The Tokenomics popup is open on the Claude tab with two bars and pace markers; the toolbar badge reads a percentage. | See your AI limits *before* you hit them. |
| 2 | The companion app window, "Turn on Tokenomics in Safari" state, with the "Open Safari Extensions…" button. Window is 440 pt wide; place it centred on a flat band with the caption above. | Turn it on *once*. |
| 3 | The popup's tab bar with eight tabs, Midjourney active, showing usage and reset time. | Eight sites. One *popup*. |
| 4 | Safari Settings > Extensions pane, Tokenomics checked, with the per-site permission list visible. | You choose which sites it *reads*. |
| 5 | Mac menu bar with Tokenomics rings and a medium widget on the desktop, Safari popup beside it. | Add the Mac app for the menu *bar*. |

Notes:
- Shots 2 and 4 are real screenshots of the real UI. Don't mock them up.
- Shot 4 shows what Safari does, not what your app does. Apple allows it as long as the screenshot is of your app's feature. If you're worried, drop it and use a close-up of the pace marker as in the Chrome plan.
- No vendor logos in any screenshot (`legal/trademark-and-claims-guide.md` section 5; Apple Guideline 5.2). Take the shots from a build with neutral glyphs or text tab labels, same as the Chrome plan. Shot 4 (Safari's own settings pane) shows only "Tokenomics", which is fine.
- Optional: an App Preview video (up to 30 seconds) showing steps 1 to 4 of "How to turn it on". Skip it for launch.

---

## 3. App Review notes

Check first: **there is no demo mode** in the extension or the Safari app. Search of the repo: demo mode exists only in the Mac app (`Tokenomics/Services/DemoModeService.swift`, `DebugMenuView.swift`) and it is gated to debug and pre-release builds (`BuildInfo.swift`). It isn't in `TokenomicsSafari` or `TokenomicsSafariExtension` and the extension's source has none. So the notes can't say "turn on demo mode". They should say what the reviewer can check without an account, and give a video and (optionally) a test account.

Paste into App Review Information > Notes:

```
Tokenomics for Safari is a companion app that contains a Safari Web Extension. The extension shows the signed-in user's own usage and limits for AI websites (Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity, Leonardo). It has no accounts of its own and collects no data.

HOW TO TEST WITHOUT AN ACCOUNT
1. Launch Tokenomics for Safari. The window says "Turn on Tokenomics in Safari". After turning the extension on in Safari, its settings page opens with a consent screen; nothing is read until "Agree and turn on" is clicked.
2. Click "Open Safari Extensions…". Safari Settings opens on the Extensions pane. Switch Tokenomics on.
3. Back in the app window, the state changes to "Tokenomics is on." and then "Waiting for your first visit to a supported site."
4. In Safari, click the Tokenomics toolbar icon. You will see one tab per supported site. Sites you are not signed in to show an empty state with a "Sign in" link to that site.
5. Click the gear icon for the per-site visibility toggles.

HOW TO SEE LIVE NUMBERS
The numbers come from the user's own account on each site, so live data needs a signed-in session. Two options:
 a) Screen recording of the full flow with live numbers: <unlisted video URL>
 b) Test account for one supported site: <site> / <username> / <password>. [Delete this line if you are not providing one.]

PRIVACY AND NETWORK
The extension contacts only the AI sites listed above, using the session the user is already signed in with, to read that user's own usage numbers. Nothing is sent to us or to any third party: no analytics, no telemetry, no accounts. The companion app has no network entitlement; its only outbound action is a button that opens https://trytokenomics.com in the user's browser. App Privacy is declared as "Data Not Collected". Privacy policy: https://trytokenomics.com/privacy

THIRD-PARTY NAMES
Tokenomics is independent and not affiliated with the services it works with. Their names are used only to identify which services are supported.

OPTIONAL MAC APP
The window footer links to our website (https://trytokenomics.com), where users can learn about a separate, free Mac menu bar app. This app does not download, install or launch other software. The extension works fully without it. If the Mac app is installed, the extension shares usage numbers with it through the App Group on the same computer.

Contact: hello@trytokenomics.com
```

Rob actions before submitting:
1. Record the video (about 60 seconds, steps 1 to 5 plus a live sign-in to one site).
2. Decide whether to include a throwaway test account (recommended: a free ChatGPT account; sending one message makes the counter show a number).
3. Fill in or delete the placeholders.

Review risk to think about: the footer link "Get the full Tokenomics app for Mac →" in `ContentView.swift` opens `https://trytokenomics.com`, where the Mac app downloads from a DMG. Apple has rules about Mac App Store apps pointing to other distribution channels. The extension code already notes this concern (`extension/src/urls.ts`). A plain link to a marketing site is commonly accepted, and the notes above explain it, but if the reviewer pushes back, the quick fix is to reword the footer to "Learn about the Tokenomics Mac app" and keep the link to the site's informational page (`/extension`), not to a download.

---

## 4. Pre-submit checklist (App Store)

- [ ] Subtitle, promo text, description, keywords, URLs, copyright pasted.
- [ ] Primary and secondary category set.
- [ ] 3 to 5 screenshots at 2880×1800 uploaded.
- [ ] App Privacy answers saved, matching the policy.
- [ ] Review notes pasted with the video link and placeholders filled.
- [ ] The Mac App Store product URL placeholder in `BrowserExtensionConnector.swift` replaced once the listing has an ID (see `in-app-copy-updates.md`).
- [ ] Release option: "Manually release after approval" so the site and the store go live together.
- [ ] App Review is typically 24 to 48 hours. That is calendar time, so submit before the Chrome review finishes and sequence the announcement around whichever clears last.
