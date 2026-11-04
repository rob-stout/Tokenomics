import SwiftUI

// MARK: - Button styles
//
// Five button variants from design-system.md section 06 (Components → Buttons).
// All use pill radius, DM Sans 16px medium (onboarding context). Hover surface
// is unified across all variants — `Tokens.Color.surface2(scheme)`.
//
// Use these via `.buttonStyle(.tokenPrimary)` etc. Anti-pattern: never use
// SwiftUI's default Button styling — that pulls Apple gray rounded chrome.

// MARK: - Button size
//
// Three size variants — design-system.md "Sizes" subsection of section 06:
//   .regular   padding: 10 × 22; font-size: 14pt    ← default `.btn`
//   .lg        padding: 14 × 36; font-size: 16pt    ← Welcome / hero CTA
//   .sm        padding:  6 × 14; font-size: 12.5pt  ← compact (back, helper)
//
// These don't all map to Tokens.Spacing.s* (which is the 8pt grid). Buttons
// use a tighter pill-friendly scale, encoded as literals here.

enum TokenButtonSize {
    case regular
    case lg
    case sm

    var horizontalPadding: CGFloat {
        switch self {
        case .regular: return 22
        case .lg:      return 36
        case .sm:      return 14
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .regular: return 10
        case .lg:      return 14
        case .sm:      return 6
        }
    }

    var font: Font {
        switch self {
        case .regular: return Font.custom("DM Sans", size: 14).weight(.medium)
        case .lg:      return Font.custom("DM Sans", size: 16).weight(.medium)
        case .sm:      return Font.custom("DM Sans", size: 12.5).weight(.medium)
        }
    }
}

/// Primary — pill, accent-ink fill (light) / brand-200 (dark), white text (light) / ink-900 text (dark).
/// `.btn-primary` in the mockup. Used for Continue, Install, Save & connect, etc.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    var size: TokenButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .foregroundStyle(scheme == .dark ? Tokens.Color.ink900 : Color.white)
            .background(Tokens.Color.accentInk(scheme))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: Tokens.Motion.fast), value: configuration.isPressed)
    }
}

/// Secondary — transparent fill, `border-strong` 1px outline, hovers to surface-2.
/// `.btn-secondary` in the mockup. Used for "I'm all set", "Try again", etc.
struct SecondaryButtonStyle: ButtonStyle {
    var size: TokenButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, size: size)
    }
}

/// Body view for `SecondaryButtonStyle`. Lifted out so we can read
/// `@Environment(\.isEnabled)` (only available inside a View, not a ButtonStyle)
/// and render disabled state with lighter token colors instead of a brute
/// `.opacity(0.6)` on the whole button (which dims text + border equally and
/// reads darker than the design target's softer disabled appearance).
private struct SecondaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let size: TokenButtonSize

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(size.font)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .foregroundStyle(textColor)
            .background(
                Capsule().fill(configuration.isPressed
                    ? Tokens.Color.surface2(scheme)
                    : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(borderColor, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: Tokens.Motion.fast), value: configuration.isPressed)
    }

    /// Disabled secondary buttons drop the text alpha to 0.80 — sits between
    /// full text (1.0) and textMuted (0.64). Heavier than a typical "muted"
    /// state so the label stays clearly legible, but visibly stepped back so
    /// the button reads as inactive.
    private var textColor: Color {
        isEnabled ? Tokens.Color.text(scheme) : Tokens.Color.text(scheme).opacity(0.80)
    }

    /// Disabled border drops from border-strong (0.22) to border (0.12) —
    /// matches the lighter outline in the mockup's disabled-state buttons.
    private var borderColor: Color {
        isEnabled ? Tokens.Color.borderStrong(scheme) : Tokens.Color.border(scheme)
    }
}

/// Ghost — transparent, text-muted, smaller padding (10×14).
/// `.btn-ghost` in the mockup. Used for "← Back" and tertiary actions.
struct GhostButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typography.Onboarding.small.weight(.medium))
            .padding(.horizontal, Tokens.Spacing.s4)
            .padding(.vertical, Tokens.Spacing.s2 + 2) // 10pt
            .foregroundStyle(Tokens.Color.textMuted(scheme))
            .background(
                Capsule().fill(configuration.isPressed
                    ? Tokens.Color.surface2(scheme)
                    : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: Tokens.Motion.fast), value: configuration.isPressed)
    }
}

/// Text link — naked link styling, accent color, optional inline arrow.
/// `.btn-text` in the mockup.
struct TextLinkButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typography.Onboarding.small.weight(.medium))
            .foregroundStyle(Tokens.Color.accent(scheme))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: Tokens.Motion.fast), value: configuration.isPressed)
    }
}

/// Button-in-field — small chip that sits inside an input or code field
/// (e.g. "Copy", "Paste"). 5pt vertical / 10pt horizontal padding, `--r-xs`
/// corners, surface-2 hover. `.btn-in-field` in the mockup.
struct InFieldButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typography.Onboarding.small.weight(.medium))
            .padding(.horizontal, Tokens.Spacing.s3 - 2) // 10pt
            .padding(.vertical, Tokens.Spacing.s1 + 1)   // 5pt
            .foregroundStyle(Tokens.Color.textMuted(scheme))
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.xs)
                    .fill(configuration.isPressed
                        ? Tokens.Color.surface2(scheme)
                        : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.xs)
                            .stroke(Tokens.Color.borderStrong(scheme), lineWidth: 1)
                    )
            )
            .animation(.easeOut(duration: Tokens.Motion.fast), value: configuration.isPressed)
    }
}

// MARK: - Convenience shorthand

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var tokenPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    /// Larger variant — `.btn-primary.btn-lg` in the mockup. Welcome / hero CTAs.
    static var tokenPrimaryLg: PrimaryButtonStyle { PrimaryButtonStyle(size: .lg) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var tokenSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var tokenSecondaryLg: SecondaryButtonStyle { SecondaryButtonStyle(size: .lg) }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var tokenGhost: GhostButtonStyle { GhostButtonStyle() }
}

extension ButtonStyle where Self == TextLinkButtonStyle {
    static var tokenTextLink: TextLinkButtonStyle { TextLinkButtonStyle() }
}

extension ButtonStyle where Self == InFieldButtonStyle {
    static var tokenInField: InFieldButtonStyle { InFieldButtonStyle() }
}

// MARK: - Preview

@MainActor
private var buttonGallery: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
        Button("Install Codex CLI") {}
            .buttonStyle(.tokenPrimary)

        Button("I'm all set — show my usage") {}
            .buttonStyle(.tokenSecondary)

        Button("← Back") {}
            .buttonStyle(.tokenGhost)

        Button("Open the guided setup →") {}
            .buttonStyle(.tokenTextLink)

        Button("Paste") {}
            .buttonStyle(.tokenInField)
    }
    .padding(Tokens.Spacing.s5)
    .background(Tokens.DynamicColor.bg)
}

#Preview("Button variants — light") {
    buttonGallery
        .frame(width: 360, height: 320)
        .preferredColorScheme(.light)
}

#Preview("Button variants — dark") {
    buttonGallery
        .preferredColorScheme(.dark)
        .frame(width: 360, height: 320)
}
