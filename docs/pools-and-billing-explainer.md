# Pools & Billing — How Tokenomics Models AI Usage

> **Purpose of this doc:** a plain-language explainer of "pools" — why different
> AI providers split usage into different buckets, how that maps to what you pay
> for, and how Tokenomics shows it. Written as source material for the website
> FAQ. It is descriptive (how the app thinks about this), not legal/billing
> advice. Exact limits and window lengths vary by provider and plan and change
> over time.

---

## The one-sentence version

A **pool** is a single usage meter — one "bucket" that fills as you use a tool and
empties when it resets. Some AI companies give you **one** pool; others give you
**several**, even under a single subscription. Tokenomics shows one progress view
per pool so you always see the meter that actually limits you.

---

## Two words to know: **brand** and **pool**

- **Brand** = the company / product family. *Anthropic, OpenAI, Google, Cursor,
  GitHub Copilot…*
- **Pool** = one usage meter inside a brand. A brand can own one pool or several.

> Think of the brand as the **bill** and a pool as a **separate meter on that
> bill** (like a house with one electric account but separate meters for the main
> house and the garage).

Tokenomics groups pools under their brand, but it tracks usage **per pool**,
because that's the level at which you actually hit a limit.

---

## The three billing patterns

Every provider Tokenomics supports falls into one of three shapes:

### 1. One brand → one pool
The simplest case: one subscription, one meter.

| Brand | Pool | Notes |
|---|---|---|
| Anthropic (Claude) | Claude | One unified meter for your Claude plan. |
| Cursor | Cursor | One meter. |
| GitHub Copilot | GitHub Copilot | One meter. |
| Stability AI, Runway, ElevenLabs, Midjourney, … | one each | Image/audio/video tools, one meter each. |

There's nothing to disambiguate here — usage is just "your usage."

### 2. One brand → one bill, **multiple** pools
You pay once, but the company meters two different products **separately**.

| Brand | Pools | Why separate |
|---|---|---|
| **OpenAI** | **ChatGPT** (web/app chat) + **Codex CLI** (coding agent) | A single ChatGPT subscription can cover both, but each is rate-limited on its own meter. Burning through ChatGPT chat does **not** drain your Codex limit, and vice-versa. |

This is the case that trips people up: *"I pay for one ChatGPT plan, why are there
two bars?"* — because OpenAI enforces two independent limits.

### 3. One brand → **separate plans**, multiple pools
The company offers two products that are billed and limited independently.

| Brand | Pools | Why separate |
|---|---|---|
| **Google** | **Gemini (app)** + **Gemini CLI** | The consumer Gemini app and the Gemini CLI are different products with their own access tiers and limits. They are not one shared bucket. |

---

## Why pools matter (the practical point)

If a company gives you several pools, **a single overall number would lie to
you.** You could be at 10% on ChatGPT chat but 95% on Codex — an "OpenAI: 52%"
average would hide the meter that's about to stop you.

So Tokenomics never averages pools together. It shows each meter on its own, and
its menu-bar / "smart" views surface the **pool closest to its limit** so the
number you glance at is the one that matters.

---

## How a pool is connected (tracking surfaces)

Pools differ not just in billing but in *how* Tokenomics reads their usage. There
are three surfaces, and they're worth knowing because they explain the small icons
in the app:

| Surface | What it means | Examples |
|---|---|---|
| 🧩 **Browser extension** | Usage is read from your signed-in web session via the Tokenomics browser companion. | ChatGPT, Gemini (app), Grok, Perplexity, Midjourney |
| ▢ **CLI / local tool** | Usage is read from a coding tool already installed on your Mac. | Claude Code, Codex CLI, Gemini CLI, Cursor, GitHub Copilot |
| 🔑 **API key** | Usage is read using a key you paste once (stored in macOS Keychain). | Stability AI, Runway, ElevenLabs |

Nothing leaves your Mac — Tokenomics reads usage counts locally and never sees
your prompts, messages, or files.

---

## How Tokenomics represents pools (surface by surface)

The same pool model shows up consistently everywhere. **One label per pool, used
in all of these places** (so the name you see never changes between screens):

- **Popover tabs** — one tab per **brand**. Tapping a multi-pool brand (OpenAI,
  Google) shows a **stacked section per pool** beneath the tab, each with its own
  bars and plan.
- **Connections settings** — brands are listed as groups. Multi-pool brands show a
  company header (e.g. *OpenAI*) with an indented **toggle per pool** so you can
  track ChatGPT and Codex independently.
- **Surface glyphs** — on multi-pool sub-rows, the pool's icon carries a small
  badge: 🧩 = browser/web pool, ▢ = CLI pool. This is how you tell apart pools
  that share a logo (both OpenAI pools use the OpenAI mark; both Google pools use
  the Gemini mark).
- **Plan pills** — each pool shows its own plan (e.g. *Pro*, *Plus*, *Free*),
  because pools can be on different tiers.
- **Notifications** — threshold alerts fire **per pool** and name the pool
  (e.g. *"Codex CLI at 90%"*), never a blended brand number.
- **Widgets** — the desktop widgets show pools the same way, with the same
  surface badges on multi-pool brands.

### Windows live *inside* a pool

Don't confuse a **pool** with a **window**. A pool can meter more than one *time
window* at once:

- A **short window** (e.g. a rolling 5-hour limit), and
- A **long window** (e.g. a weekly or 7-day limit).

These are two bars **within the same pool** — both must have headroom for you to
keep working. Tokenomics shows whichever windows a pool exposes.

---

## Quick reference

| Provider you connect | Brand | Pool(s) | Surface |
|---|---|---|---|
| Claude Code | Anthropic | Claude | CLI |
| ChatGPT | OpenAI | ChatGPT | Browser extension |
| Codex CLI | OpenAI | Codex CLI | CLI |
| Gemini (app) | Google | Gemini (app) | Browser extension |
| Gemini CLI | Google | Gemini CLI | CLI |
| GitHub Copilot | GitHub Copilot | GitHub Copilot | CLI (`gh`) |
| Cursor | Cursor | Cursor | Local |
| Stability AI | Stability AI | Stability AI | API key |
| Runway | Runway | Runway | API key |
| ElevenLabs | ElevenLabs | ElevenLabs | API key |

> **Estimated vs. exact:** almost every pool is read **exactly** — including the
> browser-extension pools (Gemini app, Grok, Perplexity, Leonardo, ElevenLabs,
> Midjourney) and the CLI pools (Claude, Codex CLI, Gemini CLI, Cursor, Copilot).
> **The one exception is ChatGPT chat.** OpenAI is the only provider that exposes
> *no* consumer-chat usage endpoint, so for that single pool Tokenomics falls back
> to counting your activity locally and shows a clearly-marked **estimate** (it can
> drift and can't see the exact reset time). Estimated values carry an
> "~estimated" indicator. Note this is ChatGPT-specific — it is **not** a property
> of "the browser extension"; the extension reads exact numbers for every other
> web pool.

---

## FAQ seeds (raw Q&A the website can adapt)

**Q: I only pay for one ChatGPT plan. Why does Tokenomics show two bars for OpenAI?**
A: OpenAI meters ChatGPT chat and the Codex coding agent on *separate* limits, even
on one subscription. They're two pools. Heavy chat use won't eat into your Codex
limit, so we show them apart — averaging them would hide whichever one is about to
run out.

**Q: Why is Gemini split into "Gemini (app)" and "Gemini CLI"?**
A: They're different Google products with their own access tiers and limits — not
one shared bucket. Each gets its own meter.

**Q: What's the puzzle-piece vs. terminal icon on some rows?**
A: It marks how that pool is tracked: 🧩 a browser/web pool (read via the Tokenomics
browser companion), ▢ a command-line tool on your Mac. It also distinguishes pools
that share a logo, like OpenAI's ChatGPT and Codex.

**Q: What's the difference between the two bars inside one pool (e.g. "5-Hour" and
"Weekly")?**
A: Those are two time windows for the *same* meter. You can hit either one — a
rolling short-term limit and a longer-term limit — so both need headroom.

**Q: Can I track just one pool of a brand?**
A: Yes. In Connections, each pool has its own toggle, so you can track Codex CLI
without ChatGPT, or either Gemini pool on its own.

**Q: Why does Tokenomics never show one combined "OpenAI %"?**
A: Because a single average would hide the meter that actually limits you. We always
show the pool closest to its limit so the glance-able number is the honest one.

**Q: Are the browser-extension numbers exact, or estimated?**
A: Exact, for every web pool *except ChatGPT*. Gemini (app), Grok, Perplexity,
Leonardo, ElevenLabs and Midjourney all read real usage numbers. ChatGPT is the
sole estimate: OpenAI doesn't expose a consumer-chat usage endpoint, so for that
one pool the extension counts your activity locally — accurate enough to be useful,
but marked "~estimated" because it can drift and can't see the exact reset moment.

**Q: Why is ChatGPT estimated when Codex (also OpenAI) is exact?**
A: They read from different places. Codex CLI has a real usage endpoint Tokenomics
reads directly; ChatGPT consumer chat has none, so it's the local-counter estimate.
Same company, two pools, two data sources — another reason we keep them separate.

**Q: Does connecting a pool send my data anywhere?**
A: No. Tokenomics reads usage counts locally on your Mac. It never sees or transmits
your prompts, messages, or files.
