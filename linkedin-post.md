# LinkedIn Post — Tokenomics (Full Origin Story)

> Status: Ready to post.

---

## POST BODY

I use Claude Code every day. For months I had no idea how close I was to my rate limit until the API started refusing requests mid-task. The only way to check was to open a browser, navigate to a dashboard, and remember what I'd done in the last five hours. That friction compounds fast when you're deep in a coding flow.

So I built Tokenomics — a macOS menu bar app that shows Claude Code API usage as two concentric rings, directly in your menu bar. The visual metaphor is borrowed from Apple Watch Activity Rings: fill clockwise as consumption grows, two rings for the two rate-limit windows (5-hour and 7-day). Any Apple user reads it instantly. No legend required.

The design decision I'm most proud of isn't the rings. It's the pace dot. A ring at 50% tells you nothing on its own — whether that's good or bad depends entirely on where you are in the window. The dot shows where the fill would be if you'd consumed evenly. If your ring is ahead of the dot, you're burning fast. If it's behind, you have room. That converts raw data into an actual signal. Three versions in, that dot has turned out to be the most useful thing in the app.

Shipping meant going beyond functional. Tokenomics is signed, notarized, and auto-updating via Sparkle — production-grade, not a side project you re-download from GitHub. Version one was working software. Versions two and three were about closing the gap between working and finished: animated bars, progressive disclosure of settings, an About view that doubles as a UI legend, and a self-healing OAuth retry that handles Claude Code's token rotation silently so you never see a logout screen.

The problem turns out not to be specific to Claude. Additional model support is coming.

Free and open source. Download at the link below.

https://github.com/rob-stout/Tokenomics/releases/tag/v1.1.1

#BuildInPublic #ProductDesign #ClaudeCode

---

## IMAGE SUGGESTION

Menu bar screenshot showing both concentric rings in a live state, with the popover open below it displaying the two usage bars with pace indicator dots visible. Ideally captured with a real usage value — not zeros — so the rings have meaningful fill. Dark menu bar preferred for contrast.

---

## STRATEGIC NOTES

**Hook rationale:** Opens mid-thought with a real-user frustration ("I use Claude Code every day") rather than a product announcement. Establishes Rob as a practitioner, not someone who built a demo.

**Beat 1 (itch + what got built):** Paragraphs 1-2. Concrete problem, concrete solution, design metaphor introduced without jargon.

**Beat 2 (why it's finished, not just functional):** Paragraphs 3-4. The pace dot as the craft signal — this is the line a design leader at Anthropic reads and understands immediately. "Signed, notarized, and auto-updating" and "three versions in" signal production maturity without listing tech specs.

**Beat 3 (what's next + CTA):** Paragraphs 5-6. Multi-model tease is one sentence, deliberately vague. Link lands cleanly.

**Signals activated without stating them:**
- Power user who noticed a gap in Anthropic's ecosystem and shipped the solution
- Ships production-quality software (signed, notarized, auto-updating)
- Thinks at the ecosystem level (multi-model coming)
- Iterates deliberately — three versions, each better than the last
- Apple Watch Activity Rings reference signals taste and design fluency

**Why this works for an Anthropic recruiter:** The post describes building on Anthropic's infrastructure, solving a real problem for Claude Code users, and thinking beyond a single product to the broader AI tool ecosystem — without once saying "I want to work at Anthropic." The work speaks for it.
