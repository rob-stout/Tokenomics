import SwiftUI

/// "Tokenomics will install X" confirmation screen.
///
/// Presented before any significant install so the user explicitly consents.
/// Layout matches mockup section 4 (Install confirms, lines 1456–1644):
///   - h2 title left-aligned, .lede description below — both OUTSIDE the surface
///   - .surface card containing: "Tokenomics will run:" label + .cmd-preview + footnote
///   - .helper "Already have X? Skip this step" — center-aligned, 12.5pt textMuted
///   - WindowFooter: ← Back ghost-sm | primary CTA (defaults to title text)
struct ConfirmInstallStep: View {
    /// Short headline. E.g. "Install Codex CLI"
    var title: String

    /// One or two sentences explaining why this is needed.
    var description: String

    /// The exact shell command Tokenomics will run, shown in a monospaced card.
    /// Nil hides the "Tokenomics will run:" label + command card.
    var commandPreview: String? = nil

    /// Muted footnote inside the surface — source, runtime, disk impact.
    var footnote: String? = nil

    /// Skip-link label. When the string contains a "?" (e.g. "Already have X? Skip this step"),
    /// the part before the "?" renders as muted helper text and the rest as a tappable text-link.
    /// When no "?" is present, the entire string is the link.
    var skipLabel: String = "I already have this"

    /// Primary button label. When nil, uses `title` (mockup pattern: "Install Codex CLI"
    /// title pairs with "Install Codex CLI" CTA). Pattern E openProviderSite passes ctaLabel explicitly.
    var primaryLabel: String? = nil

    var onContinue: () -> Void
    var onSkip: () -> Void
    var onBack: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title — h2, left-aligned, mockup line 1612 `<h3 class="h-sans h2">`
            Text(title)
                .font(Tokens.Typography.Onboarding.h2)
                .foregroundStyle(Tokens.Color.text(scheme))

            // Lede description, mockup .lede margin-top 8px
            Text(description)
                .font(Tokens.Typography.Onboarding.lede)
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tokens.Spacing.s2)

            // Surface card — only when there's a command and/or footnote to show.
            // An empty card (e.g. an install step with no shell command) reads as a
            // broken/missing element, so suppress it entirely.
            if commandPreview != nil || footnote != nil {
                surfaceCard
                    .padding(.top, 18)
            }

            // Helper — mockup .helper line 1035: 12.5px textMuted, margin-top 16px, center-aligned
            skipHelper
                .padding(.top, Tokens.Spacing.s4)
                .frame(maxWidth: .infinity)

            Spacer(minLength: Tokens.Spacing.s5)

            WindowFooter {
                if let onBack {
                    BackLink(action: onBack)
                }
            } trailing: {
                Button(primaryLabel ?? title, action: onContinue)
                    .buttonStyle(.tokenPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Surface card

    private var surfaceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cmd = commandPreview {
                // "Tokenomics will run:" label — mockup inline 12.5px textMuted, margin-bottom 6px
                Text("Tokenomics will run:")
                    .font(.custom("DM Sans", size: 12.5))
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .padding(.bottom, Tokens.Spacing.s1 + 2) // 6pt

                commandCard(cmd)
            }

            if let note = footnote {
                Text(note)
                    .font(.custom("DM Sans", size: 12.5))
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .lineSpacing(2.5) // approximates mockup line-height: 1.5
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, commandPreview == nil ? 0 : Tokens.Spacing.s3) // 12pt mockup margin
            }
        }
        .padding(.horizontal, Tokens.Spacing.s4 + 2) // 18pt
        .padding(.vertical, Tokens.Spacing.s4)        // 16pt
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Color.surface(scheme))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Tokens.Color.border(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
    }

    // MARK: - Skip helper

    @ViewBuilder
    private var skipHelper: some View {
        if let prompt = skipPrompt {
            HStack(spacing: 4) {
                Text(prompt)
                    .font(.custom("DM Sans", size: 12.5))
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                Button(skipLinkText, action: onSkip)
                    .buttonStyle(.tokenTextLink)
            }
        } else {
            Button(skipLabel, action: onSkip)
                .buttonStyle(.tokenTextLink)
        }
    }

    /// "Already have X?" portion of skipLabel (everything up to and including
    /// the first "?"). Returns nil when there's no "?" or no link suffix —
    /// caller renders the entire skipLabel as a text-link.
    private var skipPrompt: String? {
        guard let q = skipLabel.firstIndex(of: "?") else { return nil }
        let endIdx = skipLabel.index(after: q)
        let prompt = String(skipLabel[..<endIdx]).trimmingCharacters(in: .whitespaces)
        let suffix = String(skipLabel[endIdx...]).trimmingCharacters(in: .whitespaces)
        return suffix.isEmpty ? nil : prompt
    }

    /// "Skip this step" portion of skipLabel (everything after the first "?").
    private var skipLinkText: String {
        guard let q = skipLabel.firstIndex(of: "?") else { return skipLabel }
        let after = skipLabel.index(after: q)
        return String(skipLabel[after...]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Command card

    /// Dashed-border monospaced card with a `$` prompt prefix.
    /// mockup .cmd-preview (line 480): bg surface-2, dashed border-strong, r-sm, padding 12×14, mono 13px
    private func commandCard(_ command: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s2 + 2) { // 10pt
            Text("$")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Tokens.Color.textSubtle(scheme))
                .padding(.top, 1)

            Text(command)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Tokens.Color.text(scheme))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
        }
        .padding(.horizontal, Tokens.Spacing.s4 - 2) // 14pt
        .padding(.vertical, Tokens.Spacing.s3)        // 12pt
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

// MARK: - Preview

private let installStepperItems: [OnboardingStepperItem] = [
    OnboardingStepperItem(label: "Checking tools", state: .completed),
    OnboardingStepperItem(label: "Installing tools", state: .active),
    OnboardingStepperItem(label: "Signing in", state: .upcoming),
    OnboardingStepperItem(label: "Connection check", state: .upcoming),
]

#Preview("Install Homebrew — light") {
    WindowChromePreview(title: "Connect OpenAI", stepperItems: installStepperItems) {
        ConfirmInstallStep(
            title: "Install Homebrew",
            description: "Tokenomics needs Homebrew to install Codex. Homebrew is the standard Mac package manager — about 2 minutes to install.",
            commandPreview: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
            footnote: "We'll open Terminal and install Homebrew with your permission. You'll be asked for your password once. This is Homebrew's official installer, straight from brew.sh.",
            skipLabel: "Already have Homebrew? Skip this step",
            onContinue: {},
            onSkip: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.light)
}

#Preview("Install Homebrew — dark") {
    WindowChromePreview(title: "Connect OpenAI", stepperItems: installStepperItems) {
        ConfirmInstallStep(
            title: "Install Homebrew",
            description: "Tokenomics needs Homebrew to install Codex. Homebrew is the standard Mac package manager — about 2 minutes to install.",
            commandPreview: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
            footnote: "We'll open Terminal and install Homebrew with your permission. You'll be asked for your password once. This is Homebrew's official installer, straight from brew.sh.",
            skipLabel: "Already have Homebrew? Skip this step",
            onContinue: {},
            onSkip: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.dark)
}

#Preview("Install Node.js — light") {
    WindowChromePreview(title: "Connect OpenAI", stepperItems: installStepperItems) {
        ConfirmInstallStep(
            title: "Install Node.js",
            description: "Now we'll install Node.js using Homebrew. About 30 seconds, no extra permissions needed.",
            commandPreview: "brew install node",
            footnote: "Tokenomics installs Node.js into ~/.tokenomics-cli so it stays separate from any Node you might install later.",
            skipLabel: "Already have Node.js? Skip this step",
            onContinue: {},
            onSkip: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.light)
}

#Preview("Install Node.js — dark") {
    WindowChromePreview(title: "Connect OpenAI", stepperItems: installStepperItems) {
        ConfirmInstallStep(
            title: "Install Node.js",
            description: "Now we'll install Node.js using Homebrew. About 30 seconds, no extra permissions needed.",
            commandPreview: "brew install node",
            footnote: "Tokenomics installs Node.js into ~/.tokenomics-cli so it stays separate from any Node you might install later.",
            skipLabel: "Already have Node.js? Skip this step",
            onContinue: {},
            onSkip: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.dark)
}

#Preview("Install Codex CLI — light") {
    WindowChromePreview(title: "Connect OpenAI", stepperItems: installStepperItems) {
        ConfirmInstallStep(
            title: "Install Codex CLI",
            description: "Now we'll install OpenAI's Codex CLI via npm. About 30 seconds, no extra permissions needed.",
            commandPreview: "npm install -g @openai/codex",
            footnote: "This is OpenAI's official Codex CLI package on npm. Tokenomics installs it to a per-user prefix so it doesn't need admin permission.",
            skipLabel: "Already have Codex CLI? Skip this step",
            onContinue: {},
            onSkip: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.light)
}

#Preview("Install Codex CLI — dark") {
    WindowChromePreview(title: "Connect OpenAI", stepperItems: installStepperItems) {
        ConfirmInstallStep(
            title: "Install Codex CLI",
            description: "Now we'll install OpenAI's Codex CLI via npm. About 30 seconds, no extra permissions needed.",
            commandPreview: "npm install -g @openai/codex",
            footnote: "This is OpenAI's official Codex CLI package on npm. Tokenomics installs it to a per-user prefix so it doesn't need admin permission.",
            skipLabel: "Already have Codex CLI? Skip this step",
            onContinue: {},
            onSkip: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.dark)
}
