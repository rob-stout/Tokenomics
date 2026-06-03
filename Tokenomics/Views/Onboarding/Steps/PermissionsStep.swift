import SwiftUI

/// Explainer step that primes the two macOS permission prompts triggered by
/// reading Claude Code's session token from the keychain. Sits between Welcome
/// and ProviderChooser so users know what's coming before macOS interrupts.
///
/// On Continue, calls `KeychainService.probeAccess()` — that triggers the
/// keychain ACL prompt and (on macOS 15+) the "data from another app" prompt
/// at a known UI moment. The probe distinguishes three outcomes:
///   - granted (or no item exists yet) → advance to chooser
///   - denied → each surface card switches to an inline failure treatment
///     with its own deep link into the relevant Privacy pane
///
/// Per the design system "inline failure surface" pattern: 30% danger border,
/// 8% danger fill, headline in danger, body in text-muted, single concrete
/// next-step CTA per block. Two CTAs total intentionally breaks the "one CTA
/// per block" rule because the two permissions are independent — a single
/// global link would force users to re-orient between two unrelated panes.
struct PermissionsStep: View {
    var onContinue: () -> Void
    var onBack: () -> Void

    @State private var didDeny = false

    var body: some View {
        PermissionsStepBody(
            didDeny: didDeny,
            onContinue: triggerPromptsAndContinue,
            onBack: onBack
        )
    }

    /// Probes keychain access and either advances or surfaces the denied state.
    /// "Try again" routes through here too — re-firing the read so macOS can
    /// re-prompt (it does, unless the user resolved it in System Settings).
    private func triggerPromptsAndContinue() {
        switch KeychainService.probeAccess() {
        case .ok:
            didDeny = false
            onContinue()
        case .denied:
            didDeny = true
        }
    }
}

// MARK: - Stateless body
//
// Pulled out so previews can render both the initial and denied states by
// passing `didDeny` directly. PermissionsStep owns the @State flag that
// drives this in production.

private struct PermissionsStepBody: View {
    let didDeny: Bool
    let onContinue: () -> Void
    let onBack: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// One row of the permissions checklist. The same data drives both the
    /// initial explainer state and the inline failure surface — see
    /// `permissionCard(spec:didDeny:)` for how each branch renders.
    private struct RowSpec {
        let icon: String
        let title: String
        let detail: String
        let deniedTitle: String
        let deniedDetail: String
        let fixLabel: String
        let fixURL: URL
    }

    private var keychainRow: RowSpec {
        RowSpec(
            icon: "key.fill",
            title: "Keychain access",
            detail: "Lets Tokenomics read your AI provider's sign-in. Choose Always Allow so it doesn't ask again.",
            deniedTitle: "Keychain access denied",
            deniedDetail: "Tokenomics couldn't read your AI provider's session. Approve the keychain item in Keychain Access.",
            fixLabel: "Fix permission",
            // file:// URL routes through Launch Services and opens the app.
            fixURL: URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app")
        )
    }

    private var crossAppRow: RowSpec {
        RowSpec(
            icon: "rectangle.on.rectangle",
            title: "Information from another app",
            detail: "macOS treats your AI provider's keychain entry as cross-app data. One tap to allow.",
            deniedTitle: "Cross-app access denied",
            deniedDetail: "macOS blocked Tokenomics from reading another app's data. Re-enable it under App Management.",
            fixLabel: "Fix permission",
            // Privacy_AppBundles is the Privacy & Security pane that governs
            // cross-app data access on macOS 15+. Falls back gracefully on
            // older macOS — the URL still routes to Privacy & Security.
            fixURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text("Permissions needed to start tracking…")
                    .font(Tokens.Typography.Onboarding.h2)
                    .foregroundStyle(Tokens.Color.text(scheme))

                Text(didDeny
                     ? "Tokenomics can't function without these. We only use them to coordinate your computer with the AI providers for usage tracking — your information never leaves your Mac."
                     : "Tokenomics reads where your AI tools store their session info so it can show usage. The first time, macOS will pull up two separate system prompts to get your permission.")
                    .font(Tokens.Typography.Onboarding.lede)
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Tokens.Spacing.s2) {
                permissionCard(spec: keychainRow, didDeny: didDeny)
                permissionCard(spec: crossAppRow, didDeny: didDeny)
            }
            .padding(.top, Tokens.Spacing.s5)

            Spacer(minLength: Tokens.Spacing.s5)

            WindowFooter {
                BackLink(action: onBack)
            } trailing: {
                Button(didDeny ? "Try again" : "Continue", action: onContinue)
                    .buttonStyle(.tokenPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Permission card

    /// Surface card. Switches between "explainer" and "inline failure surface"
    /// styling based on `didDeny`. Failure surface follows the design system
    /// recipe: 30% danger border, 8% danger fill, headline in danger, body in
    /// text-muted, single CTA at the bottom of the text column.
    private func permissionCard(spec: RowSpec, didDeny: Bool) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s4 - 2) {
            Image(systemName: spec.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(didDeny ? Tokens.Color.danger(scheme) : Tokens.Color.accent(scheme))
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(didDeny ? spec.deniedTitle : spec.title)
                    .font(Tokens.Typography.Onboarding.body.weight(.medium))
                    .foregroundStyle(didDeny ? Tokens.Color.danger(scheme) : Tokens.Color.text(scheme))

                Text(didDeny ? spec.deniedDetail : spec.detail)
                    .font(.custom("DM Sans", size: 12))
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                if didDeny {
                    Link(destination: spec.fixURL) {
                        HStack(spacing: 4) {
                            Text(spec.fixLabel)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .font(Tokens.Typography.Onboarding.small)
                        .foregroundStyle(Tokens.Color.danger(scheme))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Tokens.Spacing.s2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Tokens.Spacing.s4)
        .padding(.horizontal, Tokens.Spacing.s5 - 4)
        .background(
            didDeny
                ? Tokens.Color.danger(scheme).opacity(0.08)
                : Tokens.Color.surface(scheme)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .strokeBorder(
                    didDeny
                        ? Tokens.Color.danger(scheme).opacity(0.30)
                        : Tokens.Color.border(scheme),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }
}

// MARK: - Preview
//
// No stepper — Permissions runs once across the whole app, while the stepper
// (Checking tools → Installing → Signing in → Connection check) is per-provider
// chrome that lives inside ConnectorView. Welcome and Chooser preview the same way.

private struct PermissionsPreviewWrapper: View {
    let didDeny: Bool

    var body: some View {
        PermissionsStepBody(didDeny: didDeny, onContinue: {}, onBack: {})
            .padding(.top, Tokens.Spacing.s6)
            .padding(.horizontal, 40)
            .padding(.bottom, Tokens.Spacing.s5 + 4)
            .frame(width: 720, height: 560)
            .background(Tokens.DynamicColor.bg)
    }
}

#Preview("Permissions — initial — light") {
    PermissionsPreviewWrapper(didDeny: false)
        .preferredColorScheme(.light)
}

#Preview("Permissions — initial — dark") {
    PermissionsPreviewWrapper(didDeny: false)
        .preferredColorScheme(.dark)
}

#Preview("Permissions — denied — light") {
    PermissionsPreviewWrapper(didDeny: true)
        .preferredColorScheme(.light)
}

#Preview("Permissions — denied — dark") {
    PermissionsPreviewWrapper(didDeny: true)
        .preferredColorScheme(.dark)
}
