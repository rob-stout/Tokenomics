import SwiftUI

/// "We're waiting for your successful login" screen shown while Terminal is open
/// and Tokenomics polls for `~/.claude/.credentials.json`.
///
/// Window 5 of the Anthropic / Claude Code flow — currently Claude-only since
/// it's the only Pattern B (external CLI auth) provider. The terminal preview
/// content is therefore Claude-specific.
///
/// Layout matches mockup section 12 Window 5 (lines 2540–2611):
///   - h2 title + lede left-aligned (lede uses Markdown bold for the "you'll
///     know you're done…" cue)
///   - Centered .terminal-mini illustration with "claude" heading + version row
///   - Centered caption "When your Terminal looks like this, you're signed in."
///   - .polling pill — dashed border, surface-2 bg, accent spinner
///   - WindowFooter: ← Back ghost-sm | "I'm signed in — check now" secondary
struct AwaitExternalAuthView: View {
    /// Short headline.
    var headline: String

    /// Instruction paragraph shown below the headline. Accepts Markdown for
    /// inline emphasis (e.g. `**You'll know you're done…**`).
    var instructionText: String

    /// Polling-pill message. Nil keeps the original Claude-specific copy
    /// ("Watching ~/.claude for authentication…") so the Claude connector's
    /// rendering is unchanged. Non-Claude connectors (e.g. Cursor) pass their
    /// own wording since "make sure you're logged in to Claude Code" doesn't apply.
    var caption: String? = nil

    /// Whether to render the Terminal-window illustration + "When your Terminal
    /// looks like this…" caption. Defaults to true (Claude's existing
    /// rendering) — false for connectors whose sign-in isn't a terminal flow
    /// (e.g. Cursor signs in inside its own app window).
    var showsTerminalArt: Bool = true

    /// Called when the user taps "I'm signed in — check now".
    var onCheckNow: () -> Void

    /// Called when the user taps Back.
    var onBack: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title — h2, left-aligned (mockup line 2568)
            Text(headline)
                .font(Tokens.Typography.Onboarding.h2)
                .foregroundStyle(Tokens.Color.text(scheme))

            // Lede with Markdown bold portion (mockup line 2569–2573)
            Text(parseMarkdown(instructionText))
                .font(Tokens.Typography.Onboarding.lede)
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tokens.Spacing.s2)

            if showsTerminalArt {
                // Centered terminal preview + caption
                VStack(spacing: Tokens.Spacing.s2 + 2) { // 10pt — mockup caption margin-top
                    terminalMiniPreview
                    Text("When your Terminal looks like this, you're signed in.")
                        .font(.custom("DM Sans", size: 11.5))
                        .foregroundStyle(Tokens.Color.textMuted(scheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Tokens.Spacing.s4) // 16pt — mockup terminal-mini margin-top
            }

            // Polling pill — dashed border, mockup line 2600
            // A touch more top padding when the terminal illustration is
            // absent — the pill otherwise sits too close under the lede.
            pollingPill
                .padding(.top, showsTerminalArt ? Tokens.Spacing.s4 - 2 : Tokens.Spacing.s5) // 14pt / 24pt

            Spacer(minLength: Tokens.Spacing.s5)

            WindowFooter {
                if let onBack {
                    BackLink(action: onBack)
                }
            } trailing: {
                Button("I'm signed in — check now", action: onCheckNow)
                    .buttonStyle(.tokenSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Markdown helper

    private func parseMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    // MARK: - Terminal mini-preview

    /// Mockup .terminal-mini lines 904–913: dark #1c1c1c bg, r-md, max-width 380, centered.
    /// Body shows Claude Code's startup signature: "claude" heading, pixel-art icon,
    /// version line, model line, project path.
    private var terminalMiniPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            terminalTitleBar

            VStack(alignment: .leading, spacing: 0) {
                // "claude" filename heading — mockup line 2581
                Text("claude")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.bottom, Tokens.Spacing.s4 - 2) // 14pt

                // Icon + version info row — mockup lines 2582–2593
                HStack(alignment: .top, spacing: Tokens.Spacing.s4 - 2) { // 14pt
                    claudePixelArtIcon

                    VStack(alignment: .leading, spacing: 0) {
                        // "Claude Code v2.1.122"
                        (Text("Claude Code")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                         + Text(" v2.1.122")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.53)))

                        Text("Opus 4.7 (1M context) · Claude Max")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(white: 0.53))

                        Text("~/projects/Tokenomics")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(white: 0.53))
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.s4 - 2) // 14pt
            .padding(.vertical, Tokens.Spacing.s3)        // 12pt
        }
        .frame(maxWidth: 380)
        .background(Color(hex: 0x1C1C1C))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .stroke(Color(hex: 0x0A0A0A), lineWidth: 1)
        )
    }

    /// Mockup .tbar (lines 915–921): 22px height, #2a2a2a bg, dark border-bottom.
    private var terminalTitleBar: some View {
        ZStack {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: 0xFF5F57)).frame(width: 8, height: 8)
                Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 8, height: 8)
                Circle().fill(Color(hex: 0x28C840)).frame(width: 8, height: 8)
                Spacer()
            }
            .padding(.horizontal, Tokens.Spacing.s2 + 2) // 10pt

            Text("Terminal — claude")
                .font(.custom("DM Sans", size: 10))
                .foregroundStyle(Color(white: 0.53))
        }
        .frame(height: 22)
        .background(Color(hex: 0x2A2A2A))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: 0x0A0A0A))
                .frame(height: 1)
        }
    }

    /// Stand-in for Claude Code's ASCII/pixel-art crab icon (mockup lines 2584–2587).
    /// 40×40 #d6916b square, 3pt radius, two 5×5 black "eyes" at (8,12) and (right:8,top:12).
    private var claudePixelArtIcon: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: 0xD6916B))
            .frame(width: 40, height: 40)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: 0x1C1C1C))
                    .frame(width: 5, height: 5)
                    .padding(.leading, 8)
                    .padding(.top, 12)
            }
            .overlay(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: 0x1C1C1C))
                    .frame(width: 5, height: 5)
                    .padding(.trailing, 8)
                    .padding(.top, 12)
            }
    }

    // MARK: - Polling pill

    /// Claude's default keeps the inline mono `~/.claude` chip (mockup line
    /// 2602); a caller-supplied `caption` renders as plain text since it has
    /// no filesystem path to monospace.
    private var pollingMessage: Text {
        if let caption {
            return Text(caption)
        }
        return Text("Watching ")
            + Text("~/.claude").font(.custom("DM Sans", size: 12).monospaced())
            + Text(" for authentication — make sure you're logged in to Claude Code.")
    }

    /// Mockup .polling lines 989–998: dashed border-strong, surface-2 bg, r-sm,
    /// padding 14×16, accent spinner + 13px textMuted message.
    private var pollingPill: some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.s2 + 2) { // 10pt
            CircularSpinner(size: 14, color: Tokens.Color.accent(scheme))

            pollingMessage
                .font(Tokens.Typography.Onboarding.small)
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Spacing.s4) // 16pt
        .padding(.vertical, Tokens.Spacing.s4 - 2) // 14pt
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Color.surface2(scheme))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .stroke(
                    Tokens.Color.borderStrong(scheme),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }
}

// MARK: - Color helper

private extension Color {
    /// Convenience init from a hex integer literal (e.g. `Color(hex: 0xFF5F57)`).
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

private let signingInStepperItems: [OnboardingStepperItem] = [
    OnboardingStepperItem(label: "Checking tools", state: .completed),
    OnboardingStepperItem(label: "Installing tools", state: .completed),
    OnboardingStepperItem(label: "Signing in", state: .active),
    OnboardingStepperItem(label: "Connection check", state: .upcoming),
]

#Preview("Window 5 — Awaiting auth — light") {
    WindowChromePreview(title: "Connect Anthropic", stepperItems: signingInStepperItems) {
        AwaitExternalAuthView(
            headline: "Confirm login",
            instructionText: "We're waiting for your successful login. **You'll know you're done when you see Claude's chat prompt** — close Terminal then and come back here.",
            onCheckNow: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.light)
}

#Preview("Window 5 — Awaiting auth — dark") {
    WindowChromePreview(title: "Connect Anthropic", stepperItems: signingInStepperItems) {
        AwaitExternalAuthView(
            headline: "Confirm login",
            instructionText: "We're waiting for your successful login. **You'll know you're done when you see Claude's chat prompt** — close Terminal then and come back here.",
            onCheckNow: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.dark)
}
