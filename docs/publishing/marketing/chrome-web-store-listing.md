# Chrome Web Store listing: Tokenomics

Everything below is paste-ready. Counts were done by hand, so run a final `pbpaste | wc -m` on each field before you submit. Status: draft, written 2026-10-27. Reconcile with `docs/publishing/legal/` once those files land (see "Open items" at the bottom).

---

## 0. Positioning in five lines (so every field says the same thing)

- **Who it's for:** people who pay for AI tools and use them in the browser (chat, voice, image). They've been cut off mid-task before, or they're afraid of it.
- **The problem:** your usage lives in a different settings page on every site. Most people don't look until they've hit the wall.
- **The promise:** one click shows what you've used, when it resets, and whether you're going too fast.
- **What's different:** eight sites in one popup, including the creative ones (Midjourney, ElevenLabs, Leonardo). A pace marker that turns a percentage into an answer. Optional sync to the Tokenomics Mac menu bar and widgets. No analytics.
- **The alternative today:** "do nothing" (check the settings page when it breaks), or one of several single-site Claude/ChatGPT trackers already in the store. Don't fight them on being first. Win on breadth, honesty about estimates, and the Mac pairing.

Competitor note (checked 2026-10-27 via web search): the store already has "AI Usage Tracker: Claude & Codex Limits", "AI Usage Tracker" (Claude, ChatGPT, Gemini, Copilot), "Claude Usage Tracker" (several), and "AI & API Usage Limit & Credit Tracker". The generic name "AI Usage Tracker" is taken. Leading with the brand name "Tokenomics" and adding "AI Usage & Limits Tracker" keeps us distinct and still searchable.

---

## 1. Store listing fields

### 1.1 Item name (also the manifest `name`)

Limit: 75 characters.

```
Tokenomics: AI Usage & Limits Tracker
```

Count: 37.

Why this one:
- Brand first, then the words people search ("AI usage", "limits", "tracker").
- No third-party brand names in the name (fixed decision).
- Chrome rejects keyword-stuffed names. This is a brand plus a plain descriptor, which is fine.

Fallback if you want it shorter (29): `Tokenomics — AI Usage Tracker`. It loses "limits", which is the word people hit when they search after getting cut off.

### 1.2 Summary (also the manifest `description`)

Limit: 132 characters. This is the line shown under the name in search results.

```
See your AI usage and limits at a glance, across the AI sites you pay for. Free, no analytics.
```

Count: 94.

Notes:
- The legal agent's trademark guide (`docs/publishing/legal/trademark-and-claims-guide.md` section 7) says the title, subtitle and short description carry "Tokenomics plus a descriptive phrase" and **no third-party names**. So I dropped the "Works with Claude, ChatGPT..." version I first drafted. The brand names live only in the detailed description, once, with the disclaimer.
- It says "usage and limits", not "exact usage". Some readings are estimates.
- "no analytics" is a factual statement about the extension. Don't change it to "no tracking" or "private" without checking the guide's section 6.

### 1.3 Detailed description

Limit: 16,000 characters, plain text only (no Markdown rendering; bullets use the "•" character). Count: about 3,300.

```
Know how much of your AI plan you've used before you hit the wall.

Tokenomics puts your usage and limits for the AI sites you pay for into one popup. Click the toolbar icon. See what you've used, when it resets, and whether you're going through it faster than an even pace.

WORKS WITH
Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity and Leonardo. Sign in to a site the way you normally do, and its meter shows up in the popup.

WHAT YOU GET
• One popup, one tab per site
• Usage bars with a pace marker. If your bar is ahead of the marker, you're using your allowance up faster than an even pace.
• Reset times, so you know when you're back
• A toolbar badge showing the percentage for the site you're closest to running out on. You can pin one site instead.
• Hide the sites you don't use in Settings

HONEST ABOUT NUMBERS
Tokenomics shows the usage numbers each site reports. Some sites only allow estimates. When a reading is an estimate, the popup labels it "estimated". We'd rather show you less than guess quietly. Numbers refresh every few minutes.

WITH THE TOKENOMICS MAC APP (OPTIONAL)
The extension works on its own. If you also install the free Tokenomics app for Mac, the two sync. Your web usage then shows in the menu bar and in desktop widgets, next to Claude Code, Codex CLI, Gemini CLI, GitHub Copilot and Cursor. One glance covers everything.

PRIVACY
• No analytics. No telemetry. No account to create.
• Tokenomics sends nothing to us. It talks only to the AI sites you use, with the sign-in you already have, and to the Mac app on your own computer if you have it.
• It saves your settings and usage numbers in your browser's extension storage on your device. For a couple of sites it also saves the access token the site gives your browser, unencrypted, so numbers can keep refreshing. It does not store your prompts or conversations.
• You can delete everything by uninstalling the extension.
Full policy: https://trytokenomics.com/privacy

PERMISSIONS, IN PLAIN WORDS
• Access to the AI sites listed above: so it can read your usage on those sites and nowhere else.
• Storage: to remember your settings and your latest numbers.
• Alarms: to refresh your numbers every few minutes.
• Native messaging: only used to talk to the Tokenomics Mac app if you have it. Chrome describes this as "communicate with cooperating native applications". Without the Mac app, nothing happens.

FREE
Tokenomics is free. No subscription, no ads.

SUPPORT
Questions or something broken? https://trytokenomics.com/faq

Tokenomics is an independent tool and is not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, Google, Midjourney, ElevenLabs, xAI, Perplexity, Leonardo.Ai, or any other AI service it works with. Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity, Leonardo, and all related names and marks are the property of their respective owners and are used here only to identify the services Tokenomics works with.
```

(The disclaimer is the legal agent's verbatim standard text, from `trademark-and-claims-guide.md` section 3. If that file changes, change this paragraph to match.)

Decisions behind this copy:
- First line is the benefit, not the feature list. The store truncates after a few lines.
- The privacy bullets are factual statements ("no data is sent to us"), not absolutes. No "100% secure", no "we can never see".
- "It does not store your prompts or conversations" is accurate to the code today: the ChatGPT watcher reads only the `model` field from the request body to count a message (`extension/src/content/chatgpt-watch.ts`). Legal should confirm the wording.
- "Free" only. It does not say "open source" (see below).
- The permissions block pre-empts the scary Chrome install dialog and the reviewer's questions.

**Do not say "open source".** `license.html` shows a custom license: free for personal use, attribution required, no redistribution or commercial use without permission. The site's own FAQ calls it "source-available". If you want to mention it, say "Source is available on GitHub" and nothing more. I left it out of the store copy to keep the page short.

### 1.4 Category and language

| Field | Value |
|---|---|
| Category | Productivity (sub-category "Tools" if the dashboard offers it; check the dropdown) |
| Language | English (United States). Add other languages later; each needs its own copy of the fields above |
| Official URL / Homepage URL | `https://trytokenomics.com/extension` (use `https://trytokenomics.com` until that page is live) |
| Support URL | `https://trytokenomics.com/faq` |
| Privacy policy URL | `https://trytokenomics.com/privacy` |
| Mature content | No |
| Price | Free |
| Visibility | Public. Optionally launch Unlisted first so you can test the install path and the Mac app handshake before announcing |

---

## 2. Privacy tab, single purpose and permission justifications

**Use the legal agent's text for this whole tab.** It is more complete than anything I would write, and it was checked against the code. Source: `docs/publishing/legal/chrome-web-store-privacy-practices.md`.

| Dashboard field | Paste from |
|---|---|
| Single purpose | Section 1 of that file |
| Permission justifications (storage, alarms, nativeMessaging, host permissions) | Section 2 |
| Remote code: "No" | Section 3 |
| Data usage boxes | Section 4. They tick **Authentication information**, **User activity** and **Website content**. Follow that, not a lighter version |
| The three certifications | Section 5 |
| Contact email, trader status | Section 7 |

Two things from that file change *marketing* work:

1. **A first-run consent screen is recommended** (their section 6), gating all polling and token capture until the user clicks "Agree and turn on". If Rob builds it (recommended), then: the reviewer test instructions below must say "click Agree", the first popup state is the consent text rather than an empty state, and screenshots should be taken after consent. Their consent text is plain and good as written. I'd only change the title to stay in the site's calm voice if you want to; I left it alone to keep the policy, dashboard and screen word-for-word aligned.
2. **Store assets must not show vendor logos** (their section 5). That changes the screenshot plan below.

Heads-up: `extension/README.md` currently says "Cookies aren't read; tokens aren't extracted." That contradicts the disclosure (ElevenLabs and Leonardo tokens are stored; ChatGPT, Claude and others use the browser session). Fix before launch; see `in-app-copy-updates.md`.

### Test instructions for the reviewer (the "Test instructions" box)

There is no demo mode in the extension. Reviewers can't see real numbers without an account. Say that plainly and give them a path.

```
Tokenomics reads the signed-in user's own usage numbers from the AI sites it lists. It has no accounts of its own and no demo mode.

To verify without special setup:
0. On install, a settings tab opens with the consent screen (also shown in the popup until accepted). Nothing is read before you click "Agree and turn on". Settings > "Stop reading and delete my data" withdraws consent and wipes storage.
1. Install and click the toolbar icon. You will see one tab per supported site. Sites you are not signed in to show an empty state with a link to sign in.
2. Open Settings (gear icon in the popup) to see the per-site visibility toggles.
3. The "Works on its own. Get the Mac app…" note at the top is expected; the Mac app is optional.

To see live numbers, sign in to any supported site with a free account and open the popup:
- chatgpt.com: send one message; the popup shows a usage reading (a message counter, labelled "estimated", if the site's exact numbers aren't available).
- claude.ai: numbers appear within a few minutes of signing in (paid plans show the 5-hour and 7-day windows).
[Optional: test account for one site: <email> / <password>. Delete this line if you won't provide one.]

A 60-second screen recording showing all of this: <unlisted video URL>.

Network: the extension only contacts the supported AI sites. No analytics or telemetry. Privacy policy: https://trytokenomics.com/privacy
```

Rob action: record the video and decide whether to supply a throwaway test account. A video plus clear steps usually clears review; an account makes it faster.

---

## 3. Screenshot plan (5 shots, 1280×800)

Rules: 24-bit PNG or JPEG, square corners, full bleed, no padding. Use made-up numbers on a clean profile. No real email, no real chat content. Show the popup at 2x then export at 1280×800 so text stays sharp.

Common frame for all five: warm cream background `#F3EFE5` (site light theme) or navy `#0E334D` (dark), a generic browser top bar with no real tabs, the popup large and centred-right, the caption set left in Hedvig Letters Serif with one italic accent word (the site's pattern). Captions are short, one idea each.

| # | Shot | Exactly what it shows | Caption (on-image) |
|---|---|---|---|
| 1 | Hero | The popup open on the Claude tab. Header shows plan badge. Two usage bars: 5-Hour at 74% with the pace marker at about 55%, 7-Day at 38% with the marker at about 45%. "Resets in 1h 36m" under the first bar. Toolbar behind it shows the badge reading "74%". | See your AI limits *before* you hit them. |
| 2 | Pace marker close-up | Zoomed crop of one usage bar with two callouts: "Where you are" pointing at the fill, "Even-pace marker" pointing at the marker. Fill ahead of the marker. | Ahead of the marker? *Slow* down. |
| 3 | Eight sites | Popup with the full tab bar visible (all eight tabs, shown as neutral glyphs or text labels, see notes). Midjourney tab active, showing Fast Hours used of total and a plan badge. | One popup. Eight *sites*. |
| 4 | Honest numbers | ChatGPT tab active with the "estimated" indicator beside the plan badge, plus the empty state for a signed-out site in a second small inset. | Estimates say so. *Always*. |
| 5 | Mac pairing | Composite: popup on the left; on the right a macOS menu bar with Tokenomics rings and one medium desktop widget. Thin line between them labelled "sync". | Add the Mac app. See it in your menu *bar*. |

Notes for whoever builds these:
- The popup shows usage **bars with a pace marker**, not rings. Rings are the Mac app's menu bar icon and widgets. Shot 5 is the only place rings appear. Don't label the popup "rings".
- **No vendor logos in any store screenshot or tile.** The legal guide (`trademark-and-claims-guide.md` section 5) is explicit: store assets use plain-text names or generic glyphs. The popup currently ships vendor logos as tab icons (`extension/src/icons/providers/*.svg`, wired in `popup.css`). Take the screenshots from a build where those icons are swapped for neutral letter monograms (or hidden, leaving text labels). A CSS override in the screenshot build is enough; it doesn't need to ship. If Rob decides to ship neutral icons in v1 too (the guide's recommendation for the first submission), the problem disappears.
- Where a tab label is needed, use the plain text name in the popup's normal font ("Claude", "Midjourney"). That is allowed nominative use.
- If any vendor name appears in a screenshot, add the short disclaimer as a small caption line: "Independent; not affiliated with or endorsed by any service it works with."
- Dark-mode variant of shot 1 is a nice A/B asset for later but not required.
- Produce at 1280×800. Also export 640×400 copies if you want a fallback.

---

## 4. Promo images

### Small promo tile (440×280): required

Concept: calm and typographic, so it reads at thumbnail size.
- Background: cream `#F3EFE5`.
- Left: Tokenomics app icon (the one in `assets/Tokenomics-logo.svg` on the site), about 72 px.
- Headline in Hedvig Letters Serif, navy `#0E334D`, two lines: "Your AI limits," / "at a *glance*." with *glance* in italic accent blue `#2F84BF`.
- Below the headline: a single usage bar graphic (fill in accent blue, a small white-ringed pace dot ahead of or behind the fill).
- No third-party logos or names. No screenshots (they turn to mush at 440×280). No small print.

### Marquee (1400×560): optional, required if you ever want to be featured

Concept: the popup at full detail on the right third, floating on a navy `#0E334D` background. Left two-thirds: headline "See your AI limits before you hit them." with *before* in italic accent, and one subline: "Eight AI sites. One popup. Free." No logos of third parties. Use the Mac menu bar strip along the bottom edge only if it doesn't crowd the text.

### Store icon (128×128)

Already in `extension/src/icons/icon-128.png`. Chrome wants the artwork at 96×96 inside a 128×128 transparent canvas. Check the existing PNG has that padding.

---

## 5. Pre-submit checklist (Chrome)

- [ ] Manifest `name` and `description` updated to 1.1 and 1.2 above. Version bumped from `0.1.0` to `1.0.0` (see `in-app-copy-updates.md`).
- [ ] **Extension ID.** The Mac app hard-codes `chrome-extension://gcjaebikgcbccgbnbcimccflcgoeefio/` in `Tokenomics/Services/NMHManifestInstaller.swift` and in `BrowserExtensionConnector.swift`. The store assigns the ID on first upload. Confirm the store ID matches, or ship a Mac app update that adds the new one. If the ID differs and nobody notices, the Mac sync silently fails for every store user. Test with an Unlisted upload first.
- [ ] The legal agent's plan is to **remove the dev `key`** for the store build (`chrome-web-store-privacy-practices.md` section 0, item 2). That changes the ID, so the Mac app's allow-list must get the new Chrome ID *and* the Edge ID before launch (`edge-addons-notes.md` section 1). Upload as Unlisted, read the ID, ship the Mac update, then go public. If you keep the `key`, check it produces the same ID in the store.
- [ ] **Confirm each of the eight sites works from the store build** before listing it. The legal guide (section 6, "Works with") says to list only services that were live-verified. My notes from `docs/extension-provider-roadmap.md` and memory say several readers (Gemini, Grok, Perplexity, Leonardo) were unit-tested against captured shapes but not all verified live. Any site that fails comes out of the description, the summary of sites on the website, and the screenshots.
- [ ] Listing text pasted, counts checked.
- [ ] 5 screenshots, small tile, (optional) marquee uploaded.
- [ ] Privacy tab: single purpose, justifications, data disclosure, privacy URL.
- [ ] Test instructions and video link.
- [ ] Submit with "Publish manually after approval" so you control the moment.

Review time is calendar time you can't compress. An extension with nativeMessaging, ten host permissions and main-world scripts will likely get a slower, closer review than a simple one. Submit early, as Unlisted if you want to test first.

---

## 6. Open items to reconcile

1. Reconciled with `docs/publishing/legal/` (trademark guide, Chrome privacy practices, Edge notes, App Store privacy label, privacy policy update) on 2026-10-27: brand-free name/summary, verbatim disclaimer, "no vendor logos" in store art, token-storage disclosure, consent screen. The legal files are labelled DRAFT pending attorney review. If they change, re-check the disclaimer paragraph and the privacy bullets in 1.3.
2. The privacy page at `https://trytokenomics.com/privacy` doesn't mention the extension yet. The legal agent has drafted the replacement copy (`privacy-policy-update.md`, section D). It must be live before you submit. See `site-update-plan.md`.
3. Is Windows/Linux Chrome supported? The facts say Chrome and Edge, nothing about platform. The copy makes no platform claim. Say yes or no and I'll add a line.
