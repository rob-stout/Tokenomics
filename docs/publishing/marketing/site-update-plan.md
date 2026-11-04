# trytokenomics.com update plan: browser extension launch

Site repo: `/Users/jarvis/projects/trytokenomics-site/` (static HTML, Cloudflare Pages). Nothing in that repo was touched. This plan names exact files and sections so a developer can implement it. Written 2026-10-27, against the files as they are today.

## Placeholders used below

| Token | Replace with | Available when |
|---|---|---|
| `{{CHROME_URL}}` | Chrome Web Store listing URL | Chrome listing exists (Unlisted works for testing) |
| `{{EDGE_URL}}` | Edge Add-ons listing URL | Edge listing exists |
| `{{APPSTORE_URL}}` | `https://apps.apple.com/app/tokenomics-for-safari/id…` | App Store record has a public ID (the record exists; the product URL works once the app is approved and released) |

Items tagged **[WAITS: URLs]** need one of these. Everything else can be built and reviewed on a branch now, and merged on go-live day. Don't merge before the URLs work; a "Get it" button that 404s is worse than no button.

Voice: the site's existing one. Calm, plain, one italic accent word per headline (`<em>`), short sentences. Kicker in caps above each H2.

---

## 1. Information architecture

Current top nav (all five pages): Features, Widgets, Install, Setup, FAQ, GitHub, plus Download button. Current pages: `/`, `/setup`, `/faq`, `/privacy`, `/license`.

Add one page: **`/extension`** (file: `extension.html`, served as `/extension` the same way `faq.html` is served as `/faq`).

Why a page and not just an index section:
- The store listings, the Mac app and the Safari app all need somewhere specific to send people ("Marketing URL").
- It gets its own SEO target ("AI usage tracker for Chrome / Safari") separate from the Mac menu bar app.
- The home page stays about the Mac app. It gets a short pointer, not a second product pitch.

Nav change on **every** page (`index.html`, `faq.html`, `setup.html`, `privacy.html`, `license.html`): in `<div class="nav-links">`, add after the Setup link:

```html
<a href="/extension">Browser</a>
```

On the new page itself, mark it `aria-current="page"`.

Footer change on every page (`<nav class="footer-links">`): add `<a href="/extension">Browser extension</a>` after Setup. `index.html` footer currently has only GitHub, Changelog, License, Privacy (lines 1159-1164). Also add Home-less links `Setup` and `FAQ` there so the footer matches the other pages.

Optional short links (Cloudflare Pages `_redirects`, 302): `/get/chrome` to `{{CHROME_URL}}`, `/get/edge` to `{{EDGE_URL}}`, `/get/safari` to `{{APPSTORE_URL}}`. Use these in posts and emails so you can change a destination without editing anything else. **[WAITS: URLs]**. Plain redirects only. Do not route them through the download-counter function in `functions/`; the privacy page discloses a counter for app downloads only, and extending it means a privacy edit. The stores' own dashboards already give you install counts.

---

## 2. New page: `extension.html`

Copy the shell from `faq.html` (head, nav, footer, `doc-hero` styles) and the section patterns from `index.html` (`feature-section`, `craft-grid`, `install-section`, `faq-item`). Reuse existing classes; add no new CSS unless the install buttons need it.

### 2.1 `<head>` and SEO

```html
<title>AI Usage Tracker for Chrome, Edge & Safari — Tokenomics</title>
<meta name="description" content="See your Claude, ChatGPT, Gemini, Midjourney and other AI usage limits in one popup. Free browser extension for Chrome, Edge and Safari. No analytics." />
<meta property="og:title" content="Tokenomics for your browser — see your AI limits at a glance" />
<meta property="og:description" content="One popup for your AI usage and limits. Free for Chrome, Edge and Safari. No analytics." />
<meta property="og:type" content="website" />
<meta property="og:url" content="https://trytokenomics.com/extension" />
<meta property="og:image" content="https://trytokenomics.com/assets/sharing/OG-Extension.png" />
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="Tokenomics for your browser" />
<meta name="twitter:description" content="Your AI usage and limits, one click away. Free for Chrome, Edge and Safari." />
<meta name="twitter:image" content="https://trytokenomics.com/assets/sharing/OG-Extension.png" />
<link rel="canonical" href="https://trytokenomics.com/extension" />
```

Counts: title 55 (limit about 60), description 150 (limit about 155).

New asset needed: `assets/sharing/OG-Extension.png`, 1200×630, same style as the promo tile (cream background, serif headline "Your AI limits, at a *glance*.", one usage bar). Until it exists, point both image tags at the current `OG-Image.png`.

Structured data (add in `<head>`):

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "Tokenomics",
  "applicationCategory": "UtilitiesApplication",
  "operatingSystem": "Chrome, Microsoft Edge, Safari on macOS",
  "description": "Browser extension that shows your AI usage and limits in one popup.",
  "offers": { "@type": "Offer", "price": "0", "priceCurrency": "USD" },
  "url": "https://trytokenomics.com/extension"
}
</script>
```

Keep the `"operatingSystem"` line honest. Edit it if Rob decides the extension is supported only on Mac, or on all desktops (open question).

### 2.2 Sections, in order

**A. Hero** (`doc-hero` pattern, or the home hero pattern if you want more presence)

- Kicker: `BROWSER EXTENSION`
- H1: `See your web AI limits at a <em>glance</em>.`
- Lede: `Your usage lives in a different place on every site. Tokenomics puts it in one popup: what you've used, when it resets, and whether you're going too fast.`
- Buttons (`btn btn-primary btn-lg`, then secondary): `Add to Chrome` (`{{CHROME_URL}}`), `Add to Edge` (`{{EDGE_URL}}`), `Get it for Safari` (`{{APPSTORE_URL}}`). **[WAITS: URLs]**
- Under buttons (small, `install-support` style): `Free. No account. No analytics.`
- Visual: the popup screenshot (Chrome shot 1) in a browser frame. Alt text: `The Tokenomics popup showing Claude usage with a pace marker`.

**B. One popup, eight sites** (`provider-section` pattern)

- H2 (small, like the home provider strip): `Works with the sites you already use`
- Strip of 8 **plain-text names, no logos**: Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity, Leonardo. Render as simple pill chips (`.pill` class), not `.provider-item` with icons. Reason: the legal guide (`legal/trademark-and-claims-guide.md` section 5) treats website hero art and logo strips like store assets: no vendor logos until an attorney clears the brand guidelines. (The home page's existing provider strip already uses logos. That's a pre-existing exposure; flag it to Rob, don't copy it onto the new page.)
- Only list sites confirmed working from the store build (see the Chrome checklist).
- Beneath: `Sign in to a site the way you normally do. Its meter shows up.`

**C. The pace marker** (`feature-section`, text left, image right; short, since the home page already explains it)

- Kicker: `SIGNAL`
- H2: `Ahead of the marker? <em>Slow</em> down.`
- Body: `A bar at 60% means nothing on its own. The pace marker shows where you'd be if you'd used your allowance evenly since the window opened. Ahead of it, you're burning through it. Behind it, you have room.`
- Image: Chrome shot 2 (the bar close-up).

**D. Honest about numbers** (`feature-section`, reversed)

- Kicker: `HONESTY`
- H2: `If it's a guess, it says so.`
- Body: `Some sites report your usage directly. Others don't, and Tokenomics can only estimate from what it sees. Estimated readings carry an "estimated" label in the popup. We'd rather show you less than guess quietly.`

**E. Pair it with the Mac app** (`feature-section`)

- Kicker: `OPTIONAL`
- H2: `Add the <em>Mac</em> app. See everything in your menu bar.`
- Body: `The extension works on its own. If you also install the free Tokenomics app for Mac, the two sync. Your web usage shows in the menu bar and desktop widgets, next to Claude Code, Codex CLI, Gemini CLI, GitHub Copilot and Cursor.`
- Link: `Get the Mac app` to `/#install`.
- Image: Chrome shot 5.

**F. What it can see, in plain words** (`craft-grid`, 3 cards; this answers the install-dialog fear)

| Kicker | Title | Text |
|---|---|---|
| Access | Only the sites listed above | `It can read your usage on those sites and nowhere else. No "all websites" permission.` |
| Session | The one you're already signed in with | `It uses your existing session to ask each site for your own usage numbers. You don't paste keys or passwords.` |
| Storage | Numbers, not conversations | `It keeps usage numbers and your settings on your device. For a couple of sites it also keeps the access token the site gives your browser. It doesn't store your prompts or chats.` |

Below the cards, link: `Full details on the privacy page` to `/privacy#browser-extension`.

**G. Chrome, Edge or Safari?** (small table, `doc-table` style from `faq.html`)

| | Chrome and Edge | Safari |
|---|---|---|
| Where you get it | Chrome Web Store / Edge Add-ons | Mac App Store, as "Tokenomics for Safari" |
| Price | Free | Free |
| Turn it on | Click Add, pin the icon | Open the app, switch it on in Safari's Extensions settings, allow the sites you want |
| Syncs with the Mac app | Yes, if installed | Yes, if installed |
| Works without the Mac app | Yes | Yes |

Edit the "Syncs with the Mac app" row for Edge once the ID question in `edge-addons-listing.md` section 2.4 is resolved. Don't leave "Yes" in if Edge sync isn't working yet.

**H. Install** (reuse `install-section` markup)

- Kicker: `Install`, H2: `Pick your <em>browser</em>.`
- Three cards: Chrome, Edge, Safari, each with its button. **[WAITS: URLs]**

**I. FAQ strip**: 4 `faq-item` entries copied from section 4 below (install, permissions, Safari vs Chrome, Mac app optional) plus a link `More answers` to `/faq#browser-extension`.

**J. Disclaimer and footer**: on this page, put the legal agent's full standard disclaimer in small text directly under the supported-sites strip (B), not only in the footer (`trademark-and-claims-guide.md` section 3, verbatim). The site footer line changes on every page to the legal agent's extended wording: `Not affiliated with, endorsed by, or sponsored by any AI service Tokenomics works with.` (`privacy-policy-update.md` section L; currently `Not affiliated with any AI service provider displayed in the app.` on all five pages).

---

## 3. `index.html` changes

Line numbers are from the file as of today.

| # | Where | Change | Waits? |
|---|---|---|---|
| 1 | `<meta name="description">` (line 7) | Append: ` Browser extension for Chrome, Edge and Safari.` | No |
| 2 | Hero CTAs (`.hero-ctas`, lines 86-101) | Add a text link row below the two buttons, same style as `install-support`: `Using AI in the browser? <a href="/extension">Get the browser extension →</a>`. The primary Download button stays the only primary CTA. | No (links to the page). Ship only with the page. |
| 3 | Provider strip footnote (line 288) `Coming soon — Midjourney, Suno, and Udio, once their public APIs ship.` | Replace with: `On the web? The <a href="/extension">browser extension</a> adds Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity and Leonardo. Suno and Udio aren't supported yet.` | With page |
| 4 | New section between the Widgets section (ends line 873) and the Craft section (starts line 879) | Add a `feature-section id="browser"`: kicker `WEB`; H2 `Not everything runs in a <em>terminal</em>.`; body `Plenty of your AI work happens in a browser tab. The Tokenomics extension shows those limits in one popup, and syncs with this app so they show up in your menu bar too.`; buttons `Add to Chrome` / `Add to Edge` / `Get it for Safari`; secondary link `How it works →` to `/extension`. **[WAITS: URLs]** for the three buttons. Until then, a single link to `/extension`. | Buttons wait |
| 5 | Install section (lines 973-1034) | Under the install tabs, add one line: `Using AI in your browser too? <a href="/extension">Add the extension →</a>`. | With page |
| 6 | FAQ item "macOS only? What about Windows and Linux?" (lines 1096-1106) | Add to the end of the answer: `The browser extension is a separate piece. See the <a href="/extension">extension page</a> for where it runs.` Pending Rob's answer on Windows/Linux Chrome. | With page |
| 7 | FAQ item "What about Midjourney, Suno, or Udio?" (lines 1108-1118) | **Rewrite. The current answer is now wrong.** It says Tokenomics "won't integrate against unofficial endpoints or scraping", but the extension reads Midjourney through its web session. Proposed answer: `Midjourney works through the browser extension, which reads the usage shown in your own Midjourney account, using your signed-in session. Suno and Udio aren't supported yet.` I left out any claim about Midjourney having no public API, since I haven't verified it, and any "allowed" language, per the legal guide. | With page |
| 8 | Hero lede and OG text ("Eight providers") (lines 9, 13) | Don't change the number until you decide what to count (app providers only, or app plus extension). Leave as is. | No |
| 9 | "Does it send my API keys or credentials anywhere?" answer (lines 1078-1081) | Add: `The browser extension is covered separately on the <a href="/privacy#browser-extension">privacy page</a>.` Also note this answer says outbound calls are only to Anthropic and GitHub, but the privacy page lists more (Cursor, Stability, Runway, ElevenLabs). That mismatch exists today and is worth fixing in the same pass. | No |
| 10 | Footer (lines 1159-1164) | See section 1. | No |

---

## 4. `faq.html` additions

Add a new group after "Accounts & privacy" and before the `faq-contact` block (line 361). Anchor: `id="browser-extension"` on the group `<h2 class="faq-group">`.

Also, **each new Q&A needs three edits**: the HTML answer, a line in the "On this page" `faq-toc` list, and an entry in the `FAQPage` JSON-LD at the top (lines 32-95). The JSON-LD is hand-maintained and must match the visible text.

`<h2 class="faq-group" id="browser-extension">The browser extension</h2>`

**Q: How do I install the browser extension?** (`id="ext-install"`)
> In Chrome, open the Tokenomics page on the Chrome Web Store and click Add to Chrome. In Edge, use the Edge Add-ons page. Then pin the Tokenomics icon from the puzzle-piece menu so it stays in your toolbar. In Safari, install Tokenomics for Safari from the Mac App Store, open it, and switch the extension on in Safari's Extensions settings. Sign in to the AI sites you use, and their meters appear in the popup. Links to all three are on the <a href="/extension">extension page</a>. **[WAITS: URLs]** for the links only.

**Q: What does the extension have access to?** (`id="ext-permissions"`)
> Only the AI sites it works with: Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity and Leonardo. It doesn't ask for access to all websites. On those sites it reads your own usage and limit numbers, using the sign-in you already have. It saves your settings and latest numbers in your browser's extension storage on your device, and for a couple of sites it also saves the access token the site gives your browser. Numbers refresh every few minutes.

**Q: Why does it need access to the AI sites?** (`id="ext-why-sites"`)
> Each site shows your usage in its own account pages, with no shared way to get it. To show it in the popup, the extension has to ask that site for your numbers, the same way the site's own pages do. That is the only reason it has access to those sites. It doesn't touch any others.

**Q: Why does Chrome say it can "communicate with cooperating native applications"?** (`id="ext-native"`)
> That's the permission the extension uses to hand your usage numbers to the Tokenomics Mac app, if you have it installed. Without the Mac app, nothing happens. It lets the web usage show up in your menu bar and widgets.

**Q: Does it see my chats or prompts?** (`id="ext-chats"`)
> The extension reads usage numbers, not conversations. It doesn't store your prompts or chats. On ChatGPT it counts a message when you send one and notes which model it used. It does not keep what you wrote. Details are on the <a href="/privacy#browser-extension">privacy page</a>.

**Q: Is any of my data sent to Tokenomics?** (`id="ext-data"`)
> No. There's no analytics or telemetry in the extension. It talks only to the AI sites you use, plus the Mac app on your own computer if you have it. The privacy page lists exactly what it connects to.

**Q: Are the numbers exact?** (`id="ext-exact"`)
> Not always. Some sites report your usage directly. Others don't, and Tokenomics can only estimate. When a reading is an estimate, the popup shows an "estimated" label next to the plan.

**Q: Does it work without the Mac app?** (`id="ext-standalone"`)
> Yes. The extension works on its own in your browser. The Mac app adds menu bar rings and desktop widgets, and brings in Claude Code, Codex CLI, Gemini CLI, GitHub Copilot and Cursor. If you have both, they sync.

**Q: Should I get the Chrome version or the Safari version?** (`id="ext-safari-chrome"`)
> Use whichever browser you use. They do the same job. Chrome and Edge get it from their browser's store. Safari gets it from the Mac App Store as "Tokenomics for Safari", which is a small app that contains the Safari extension. If you use both browsers, you can install both.

**Q: Does the AI service allow this?** (`id="ext-allowed"`)
> Tokenomics is independent and unofficial. It uses your own signed-in session to read your own usage. Each service has its own terms; please read them. (Wording from `legal/trademark-and-claims-guide.md` section 6. Don't add "safe", "allowed" or "approved".)

**Q: Is Tokenomics affiliated with Anthropic, OpenAI, Google or the others?** (`id="ext-affiliation"`)
> No. Put the legal agent's full standard disclaimer here, verbatim.

**Q: Which browsers does it work in?** (`id="ext-browsers"`)
> Chrome, Edge and Safari. [Rob: add or leave out Brave, Arc, Vivaldi, Opera? The Mac installer already writes the bridge file for those browsers, but they aren't in the supported list yet, so I haven't claimed them.]

---

## 5. `setup.html` changes

| # | Where | Change |
|---|---|---|
| 1 | Nav (line 449-456) | Add Browser link (section 1). |
| 2 | Hero lede (line 482-484) | Append one sentence: `Using AI in the browser? Add the <a href="#browser-extension">browser extension</a> too.` |
| 3 | TOC grid (`.guide-toc`, lines 487-552) | Add a seventh item after "Stability · Runway · ElevenLabs": name `Browser extension`, sub `Chrome · Edge · Safari`, `href="#browser-extension"`, with the Tokenomics mark as the icon. |
| 4 | New section after the `api-key` section | `guide-section id="browser-extension"`, same markup as the others (`step-list`, `step-title`, `step-body`, `step-expect`, `step-tip`). Steps below. |
| 5 | Anthropic, OpenAI and Google sections (`#anthropic`, `#openai`, `#google`) | In each section's "what you need" list, add one bullet: `Use it on the web? The <a href="#browser-extension">browser extension</a> reads your usage there.` |

Section 4 steps (**[WAITS: URLs]** for the links in step 1):

- Header: `Browser extension` (`<em>Browser</em> extension`). Needs: "A free Chrome, Edge or Safari. About 2 minutes."
- Step 1, **Install it.** Chrome and Edge: "Open the extension page, click Add, and pin the Tokenomics icon." Safari: "Install Tokenomics for Safari from the Mac App Store." Link to `/extension`.
- Step 2, **Turn it on in Safari (Safari only).** "Open Tokenomics for Safari and click Open Safari Extensions. Switch Tokenomics on, then allow it on the sites you want it to read." `step-expect`: "The app window changes to 'Tokenomics is on.'"
- Step 3, **Sign in to your AI sites.** "Visit the sites you use and sign in the way you normally do. Their meters appear in the popup within a few minutes." `step-tip`: "ChatGPT: send one message to start the counter. Estimated readings carry an 'estimated' label."
- Step 4, **(Optional) Connect the Mac app.** "If Tokenomics for Mac is installed, it detects the extension automatically. Its first-run setup also has an Install the extension step." `step-expect`: "The extension footer shows 'Tokenomics' and the version number."

The Mac app's own onboarding step is `Install the browser extension` (`BrowserExtensionConnector.swift`). Describe it as part of the Quick and Guided flow, since the page already has that tab structure. Add the same steps to the Terminal tab variant only if you want a non-guided alternative; none is needed.

---

## 6. `privacy.html` changes

The privacy page is the policy URL for both stores, and today it says nothing about the extension. It must be updated **before the stores' review**, and reviewers will read it. The legal agent has written the replacement copy in `docs/publishing/legal/privacy-policy-update.md`. **Paste that copy; don't write a second version.** It also corrects overclaims already on the page ("nothing is persisted to disk", "no third-party SDKs", the Google Fonts line, "open source").

Where each of their sections lands (section letters are theirs):

| Their section | Goes where in `privacy.html` | Notes |
|---|---|---|
| A. Hero lede and meta | Lede (line 252), `<title>`, `og:description`, effective date (line 256) | Remove "No third-party SDKs" from the og text. |
| B. "What this policy covers" | New first section above "What Tokenomics accesses" (line 271) | Names all four things: Mac app, extension, Safari app, website. |
| C. Mac app sections | Existing sections, lightly edited | Includes the line 333 text about Midjourney placeholder tiles, which is now out of date. |
| D. "Browser extension (Chrome and Edge)" | After the Mac app network calls | **Give this `<h2>` `id="browser-extension"`** so `/extension` and the FAQ can deep-link to `/privacy#browser-extension`. It documents the stored tokens. |
| E. "Tokenomics for Safari" | Right after D | Give it `id="safari"`. |
| F. "About this website" | Existing section, plus a line saying the stores' installs don't touch the download counter | Keeps the website counter clearly separate from the app and extension (Rob's rule). Their fonts fix (self-host, or disclose) applies here. Pick the counter retention number. |
| G, H, I, J, K | "Does NOT do" list, data retention, new sections, changes, contact | As written. |
| L. Footer, all pages | `footer-meta` on all five pages | `Not affiliated with, endorsed by, or sponsored by any AI service Tokenomics works with.` |

Two things from the line-by-line read of the page that their copy covers but are easy to miss:
- Line 414 says `the source code is open`; their notes say to use "source-available" in public copy.
- The "Verifying any of this yourself" callout (line 414) tells people to run Little Snitch and see only the listed endpoints. After D lands, the endpoints list must include the extension's sites or that callout is wrong.

The store policy URL stays exactly `https://trytokenomics.com/privacy` (no hash). Use the hash only on-site.

---

## 7. Sitemap and SEO files

`sitemap.xml`: add after `/setup`:

```xml
<url>
  <loc>https://trytokenomics.com/extension</loc>
  <changefreq>monthly</changefreq>
  <priority>0.8</priority>
</url>
```

`robots.txt`: no change.
`_redirects` (see section 1): optional short links.
`site.webmanifest`: no change.
Internal links to `/extension`: nav (5 pages), footer (5 pages), home hero, home install, setup TOC, FAQ. That's 15 or more internal links, which is enough for a new page.
Google Search Console: after deploy, request indexing for `/extension` and resubmit the sitemap.

---

## 8. Order of work

1. **Now, on a branch (no URLs needed):** build `extension.html`, nav/footer links, `index.html` changes 1 to 10, `faq.html` group, `setup.html` section, `privacy.html` section (with the legal agent's text), sitemap. Use the placeholder tokens.
2. **Before submitting to stores:** the privacy page update must be live, since the stores' policy URL points at it. This is the one piece that must ship *before* store review, not after. Deploy privacy + FAQ only (they don't depend on URLs).
3. **When each store URL exists:** replace tokens, add `_redirects` short links.
4. **Go-live day:** merge the branch, check every button, resubmit sitemap, post.

---

## 9. Launch-announcement checklist

Calendar time you can't compress: Chrome review (days; this extension has nativeMessaging and ten host permissions, so don't assume the fast path), Edge review, App Review (typically 24 to 48 hours). Plan around whichever clears last. Don't announce a store that isn't live yet.

**Before submitting**
- [ ] Privacy page updated and deployed (section 6, using the legal agent's copy).
- [ ] First-run consent screen decision made (legal recommends it; the reviewer test steps and screenshots depend on it).
- [ ] Extension IDs read from unlisted Chrome and Edge uploads, both added to the Mac app's allow-list, Mac update shipped (see `chrome-web-store-listing.md` section 5 and `edge-addons-listing.md` section 2.4).
- [ ] Each of the eight sites verified working from the store build; any that fail removed from every surface.
- [ ] Vendor logos removed from store art (and the website's new page).
- [ ] Review video recorded; optional test account created.
- [ ] Screenshots, tiles, OG image made.
- [ ] README in `extension/` corrected (see `in-app-copy-updates.md`).

**While in review**
- [ ] Website branch finished, tokens in place.
- [ ] Announcement copy drafted (below).
- [ ] Ask 5 to 10 people you know to test the Unlisted Chrome build. Ask for reactions, not upvotes.
- [ ] Mac app update ready if needed: real App Store URL in `BrowserExtensionConnector.swift`, new footnote, release notes line.

**Go-live day**
- [ ] Replace tokens, merge, deploy. Click every store button from a clean browser.
- [ ] Set Chrome and Edge listings public; release the Safari app.
- [ ] Release the Mac app update (Sparkle) with a one-line mention of the extension.
- [ ] Post: LinkedIn (origin story and the design angle), X, and one forum post below. Reply to every comment for the first six hours.
- [ ] Update GitHub README with the three install links. Add the extension to the Homebrew cask description only if relevant (it isn't; skip).
- [ ] Tell the site's Search Console to re-index.

**After**
- [ ] Watch the store dashboards for install counts and reviews. Reply to every review.
- [ ] Collect "it said estimated but..." type feedback; those are your bug reports for the readers.
- [ ] Week 2: add a short "What's new" line to the extension page once you have a changelog.
- [ ] Add the extension to the portfolio log (the privacy-first, honest-about-estimates decisions are good case-study material).

**Where to post** (read each community's self-promotion rules first; ask a moderator if unsure)
- r/ClaudeAI: lead with the pace marker and the 5-hour/7-day windows.
- r/MacApps: lead with "menu bar + Safari + widgets".
- Show HN: only if the Mac app's Show HN is more than a few weeks old; HN doesn't like repeat posts. Lead with the technical story (reading usage with no public API, the "estimated" label).
- Previous plan (`launch-plan.md`) says avoid r/SideProject and launch-coordination subs. Same here.
- Product Hunt: the Mac app's launch plan exists. Open question whether the extension is a new launch or an update to the existing listing.

**Copy kit** (short; adapt per channel)

One-liner: `Tokenomics now has a browser extension. One popup shows your AI usage and limits for Claude, ChatGPT, Gemini, Midjourney and more. Free for Chrome, Edge and Safari.`

LinkedIn/X post:
> I kept finding out about AI limits by hitting them. The Mac app fixed that for coding tools. But half my AI work is in a browser tab, so I built the same thing for the web.
>
> The Tokenomics extension puts your usage, your reset times and a pace marker in one popup. Chrome, Edge and Safari. Free. No analytics.
>
> It says "estimated" when it's guessing. I'd rather show you less than fake it.
>
> trytokenomics.com/extension

Reddit (r/ClaudeAI): lead with the problem, not the product.
> Title: I built a browser extension that shows your 5-hour and 7-day Claude limits (and the other AI sites you use) in one popup
> Body: first-person story, one screenshot of the pace marker, one line on privacy ("no analytics, talks only to the sites you use"), the link, and "happy to hear what's broken."

Do not claim "exact usage", "100% private" or "open source" in any post.
