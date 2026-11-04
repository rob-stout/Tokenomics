# Edge Add-ons listing: deltas from Chrome

Use `chrome-web-store-listing.md` as the base. Same package, same name, same summary, same description. This file lists only what differs. Written 2026-10-27 and reconciled with `docs/publishing/legal/edge-addons-notes.md` (same conclusions on the extension ID, search terms, category and reviewer notes). For privacy text, single purpose and permission justifications, paste from `legal/chrome-web-store-privacy-practices.md` sections 1 to 5, as for Chrome.

Source for the Edge field specs below is Microsoft's Edge extensions docs plus one third-party guide (TurboStarter). The numeric limits marked "(unverified)" came from the third-party guide, so check them in Partner Center when you fill the form: https://learn.microsoft.com/en-us/microsoft-edge/extensions/

---

## 1. What stays identical

| Field | Value |
|---|---|
| Name | `Tokenomics: AI Usage & Limits Tracker` (37) |
| Short description | `See your AI usage and limits at a glance, across the AI sites you pay for. Free, no analytics.` (94) |
| Privacy policy URL | `https://trytokenomics.com/privacy` |
| Support / website URL | `https://trytokenomics.com/faq` (support), `https://trytokenomics.com/extension` (website) |
| Price | Free |
| Language | English (United States) |

## 2. What changes

### 2.1 Description

Description length for Edge is 250 to 5,000 characters (unverified). The Chrome description (about 2,900) fits. Use it unchanged, with two edits:

1. In "WITH THE TOKENOMICS MAC APP", no change needed. Edge on Mac works with the Mac app the same way, as long as the ID issue in 2.4 is resolved.
2. Add one line at the very end, before the non-affiliation sentence:

```
Also available for Chrome and, as a separate app, for Safari ("Tokenomics for Safari" on the Mac App Store).
```

Edge reviewers don't mind cross-references. Users do like knowing where else it runs.

### 2.2 Category

Edge category: **Productivity**. (Edge has a smaller category list than Chrome. Pick Productivity.)

### 2.3 Search terms

Edge has a "Search terms" field (up to about 7 terms and 21 words; unverified). Use:

```
AI usage, usage limits, rate limit, quota tracker, AI tracker, usage monitor, token usage
```

7 terms, 15 words. No third-party brand names in search terms.

### 2.4 Extension ID and the Mac app: the one real difference

Edge Add-ons assigns its own extension ID. It will very likely differ from the Chrome ID. The Mac app only lets one origin talk to its bridge: `chrome-extension://gcjaebikgcbccgbnbcimccflcgoeefio/` (`Tokenomics/Services/NMHManifestInstaller.swift`, line 23). The installer already writes the manifest into Edge's `NativeMessagingHosts` folder, but with that same Chrome-only ID in `allowed_origins`.

What that means: an Edge user who installs from Edge Add-ons gets a working popup, but Mac sync fails, because the Edge ID isn't allowed.

Microsoft's native messaging guide says to update `allowed_origins` with the published ID if it changed after publishing: https://learn.microsoft.com/en-us/microsoft-edge/extensions-chromium/developer-guide/native-messaging

The legal agent plans to drop the dev `key` for store builds, which means Chrome's store ID will also differ from the one in the Mac app. So the plan is:
1. **Upload to each store as unlisted/hidden, read the assigned IDs, add both to `allowedOrigins`, ship a Mac app update, then go public.** Edge sync works for store users only after that Mac release.
2. (Alternative, unverified) Keep the same `key` and see whether Edge gives the same ID. I couldn't confirm this from documentation. Only worth testing if you want to avoid the Mac release.

Until one of these is done, don't claim "syncs with the Mac app" in the Edge description. Remove the Mac-app section, or add "(Chrome and Safari)" after "syncs". Rob decision, see open questions.

Edge users can also install the Chrome Web Store version directly (Edge offers "Allow extensions from other stores"). Those users keep the Chrome ID and sync works. That is the cheapest launch path for Edge: point Edge users to the Chrome listing and publish the Edge listing once the ID is sorted.

### 2.5 Images

| Asset | Edge spec | Use |
|---|---|---|
| Store logo | 300×300 PNG (unverified) | Export the app icon at 300×300 |
| Screenshots | Up to 10, 1280×800 or 640×480 (unverified) | The 5 Chrome screenshots at 1280×800. Swap the browser chrome in the frame for an Edge-style top bar. |
| Small promo tile | 440×280. Microsoft's docs list it as required; the third-party guide calls it optional. Provide it | Same tile as Chrome |
| Large promo tile | 1400×560, optional | Same as the Chrome marquee |
| Video URL | Optional YouTube link | The 60-second review video, if you make it public |

Screenshots: in shots 1, 3 and 5, show the popup next to the Edge address bar and extensions menu, not Chrome's. Don't ship Chrome-branded frames to Edge. Same rule as Chrome: no vendor logos in store art (use neutral glyphs or text tab labels).
Microsoft makes Copilot, and Copilot is one of the Mac app's tools. Keep any Edge text neutral and non-comparative, as the legal notes say.

### 2.6 "Notes for certification" field

Edge has a free-text box for testers. Reuse the Chrome "Test instructions" text. Change step 1 to say "Install and click the Tokenomics icon in the Edge toolbar (pin it from the Extensions menu)."

### 2.7 Review timing

Edge review is also calendar time. Expect several business days; don't plan around a specific number.

---

## 3. Edge-specific pre-submit checklist

- [ ] Decide on the ID plan in 2.4 and write the Mac-app sentence accordingly.
- [ ] Upload the same zip used for Chrome. If the `key` field breaks the Edge upload, remove it for Edge only.
- [ ] 300×300 logo exported.
- [ ] Screenshots reframed for Edge.
- [ ] Search terms entered.
- [ ] Privacy URL, support URL, test notes entered.
