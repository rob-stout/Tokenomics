import SwiftUI
import AppKit

/// Explainer step that primes the ONE macOS prompt triggered by reading Claude
/// Code's session token from the keychain. Sits between Welcome and ProviderChooser
/// so users know what's coming before macOS interrupts.
///
/// (The macOS 15 "access data from other apps" prompt is NOT ours to prime: reading
/// the keychain or credentials file can't cause it. It comes from App Group container
/// access, which the release provisioning profile authorizes.)
///
/// On Continue, calls `ClaudeCredentialStore.requestAccess()` — that triggers the
/// keychain ACL prompt at a known UI moment. The probe distinguishes:
///   - granted (or no item exists yet) → advance to chooser
///   - denied → the keychain card switches to an inline failure treatment;
///     "Try again" re-fires the read so macOS can re-prompt
///
/// Per the design system "inline failure surface" pattern: 30% danger border,
/// 8% danger fill, headline in danger, body in text-muted.
struct PermissionsStep: View {
    var onContinue: () -> Void
    var onBack: () -> Void

    @State private var didDeny = false
    /// Identifies the in-flight attempt. Back clears it, so a dialog result that lands
    /// after Back (even after returning to this step) can't advance — only the latest
    /// attempt may.
    @State private var attemptID: UUID?

    var body: some View {
        PermissionsStepBody(
            didDeny: didDeny,
            isRequesting: attemptID != nil,
            onContinue: triggerPromptsAndContinue,
            onSkip: skipKeychainAccess,
            onBack: {
                attemptID = nil
                onBack()
            }
        )
    }

    /// Continues without Claude keychain access. Claude can be connected later from the
    /// popover or Settings "Allow Access", so users who don't use Claude aren't stranded
    /// here. Clearing `attemptID` invalidates any in-flight dialog result. Nothing
    /// downstream reads the keychain interactively on its own, so no dialog follows.
    private func skipKeychainAccess() {
        attemptID = nil
        didDeny = false
        onContinue()
    }

    /// Asks for keychain access and either advances or surfaces the denied state.
    /// "Try again" routes through here too — re-firing the read so macOS can
    /// re-prompt (it does, unless the user resolved it in System Settings).
    /// The read runs off the main thread (the store's private queue), so the UI
    /// stays responsive while the dialog is up; a non-nil `attemptID` blocks double-taps.
    private func triggerPromptsAndContinue() {
        guard attemptID == nil else { return }
        let id = UUID()
        attemptID = id
        Task {
            let result = await ClaudeCredentialStore.shared.requestAccess()
            // The user may have navigated Back while the macOS dialog was up.
            guard attemptID == id else { return }
            attemptID = nil
            // No keychain item yet (Claude Code not signed in) is fine — nothing to deny.
            switch result {
            case .found, .notFound, .staleToken:
                // A stale token isn't a denial; the connector's re-login path handles it.
                didDeny = false
                onContinue()
            case .needsAuthorization:
                didDeny = true
            }
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
    var isRequesting = false
    let onContinue: () -> Void
    var onSkip: () -> Void = {}
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

    /// Keychain Access moved to /System/Library/CoreServices/Applications on macOS 26.
    /// Resolve by bundle id so we follow it wherever the OS puts it; the file:// URL
    /// routes through Launch Services and opens the app.
    private static var keychainAccessURL: URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.keychainaccess")
            ?? URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Keychain Access.app")
    }

    private var keychainRow: RowSpec {
        RowSpec(
            icon: "key.fill",
            title: "Keychain access",
            detail: "Lets Tokenomics read your Claude Code sign-in. macOS may ask twice. Enter your Mac password and choose \"Always Allow\" each time.",
            deniedTitle: "Keychain access denied",
            deniedDetail: "Tokenomics couldn't read your Claude Code sign-in. Click Try again and choose \"Always Allow\" when macOS asks.",
            fixLabel: "Open Keychain Access",
            fixURL: Self.keychainAccessURL
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text("Permissions needed to start tracking…")
                    .font(Tokens.Typography.Onboarding.h2)
                    .foregroundStyle(Tokens.Color.text(scheme))

                Text(didDeny
                     ? "Tokenomics needs this to show your Claude usage. We only use it to coordinate your computer with the AI providers for usage tracking — your information never leaves your Mac."
                     : "Tokenomics reads where your AI tools store their session info so it can show usage. The first time, macOS may ask twice. Enter your Mac password and choose \"Always Allow\" each time.")
                    .font(Tokens.Typography.Onboarding.lede)
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Tokens.Spacing.s2) {
                permissionCard(spec: keychainRow, didDeny: didDeny)
            }
            .padding(.top, Tokens.Spacing.s5)

            Spacer(minLength: Tokens.Spacing.s5)

            WindowFooter {
                BackLink(action: onBack)
            } trailing: {
                HStack(spacing: Tokens.Spacing.s3) {
                    if didDeny {
                        Button(action: onSkip) {
                            Text("Skip for now")
                                .font(Tokens.Typography.Onboarding.small)
                                .foregroundStyle(Tokens.Color.textMuted(scheme))
                                .padding(.horizontal, Tokens.Spacing.s3)
                                .padding(.vertical, Tokens.Spacing.s2)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button(didDeny ? "Try again" : "Continue", action: onContinue)
                        .buttonStyle(.tokenPrimary)
                        .disabled(isRequesting)
                }
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
