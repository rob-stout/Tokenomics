# Tokenomics

**See how much of your AI usage limits you've used, right in your Mac menu bar.**
Claude, ChatGPT, Gemini, GitHub Copilot, Cursor and more, with a pace dot that shows whether you'll run out before the limit resets. Free.

**[trytokenomics.com](https://trytokenomics.com)** · [Download for macOS](https://trytokenomics.com/download/dmg/latest) · [Chrome extension](https://chromewebstore.google.com/detail/tokenomics-ai-usage-limit/nolficmmhjkgmoclepbclpmefilhlejl) · [Help](https://trytokenomics.com/help/)

<img width="330" height="313" alt="The Tokenomics popover showing Claude's 5-hour and 7-day usage" src="https://github.com/user-attachments/assets/87938acc-e2d9-4bce-9ee7-a0ef1a66a44b" />

---

## What it tracks

| Where | Tools | How it connects |
|---|---|---|
| **Mac app** | Claude Code, Codex CLI, Gemini CLI, GitHub Copilot, Cursor | The sign-in each tool already keeps on your Mac (Claude Code's in the macOS Keychain, the `gh` CLI for Copilot, local config files for the rest) |
| **Mac app** | Stability AI, Runway | An API key you paste once |
| **Browser extension** | ChatGPT, Claude, Gemini, Midjourney, Leonardo, ElevenLabs, Suno, Udio, Grok, Perplexity | The sites you're already signed in to |

Run both and they share one set of numbers: web tools show up in your menu bar and widgets too. [Full list, and what each tool shows](https://trytokenomics.com/help/supported-tools).

## Features

- **Menu bar rings.** The inner ring is the short window (like Claude's 5 hours), the outer ring the long one (like the 7-day window). The number is the limit you're closest to.
- **Pace dot.** Where your usage would sit if you'd used the limit evenly since it reset. Past the dot means you'll run out early. [More](https://trytokenomics.com/help/pace-dot)
- **Desktop widgets** in three sizes, for one, three or seven tools.
- **Usage alerts** before you hit a limit, and a small celebration when one resets.
- **Updates itself** (Sparkle), when you say so.

## Install

```bash
brew install rob-stout/tap/tokenomics
```

Or [download the .dmg](https://trytokenomics.com/download/dmg/latest), open it and drag Tokenomics to Applications. Requires macOS 14 Sonoma or later. Developer ID signed and notarized.

On first launch, Tokenomics finds the tools you have and walks you through connecting them. The [setup guide](https://trytokenomics.com/setup) has the steps for each tool and fixes for every error message.

The browser extension is on the [Chrome Web Store](https://chromewebstore.google.com/detail/tokenomics-ai-usage-limit/nolficmmhjkgmoclepbclpmefilhlejl) and works in Chrome, Brave, Arc, Vivaldi and Opera, on Mac, Windows or Linux, with or without the Mac app. Edge and Safari versions are on the way.

## Privacy

No analytics, no telemetry, no third-party SDKs. Tokenomics reads your usage from each service with the sign-ins you already have, and shows it on your device. It never reads your chats. [Privacy policy](https://trytokenomics.com/privacy)

## Help and feedback

- [Help center](https://trytokenomics.com/help/): every question, searchable
- Bugs and ideas: [open an issue](../../issues) or email hello@trytokenomics.com

## Support

Tokenomics is free. If it saves you from a surprise rate limit, consider [sponsoring its development](https://github.com/sponsors/rob-stout).

## License

Source available: free to use and share with attribution. See [LICENSE](LICENSE).

Tokenomics is not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, Google, GitHub, Cursor or any other AI service it works with.
