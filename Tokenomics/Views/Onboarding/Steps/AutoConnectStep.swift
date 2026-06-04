import AppKit
import SwiftUI

/// "Already connected" — the auto-connect explainer.
///
/// Sits between MultiSelect and SetupPlan. For providers that are already
/// installed AND signed in (Claude Code, Cursor, Copilot, Codex/Gemini CLI), we
/// can read usage with zero user interaction. This screen visibly checks those
/// off — pacing the presentation of work that genuinely happened (`checkConnection`
/// validated each one live) so the user perceives "it found my stuff and
/// connected it for me", then hands off to only the steps that still need them.
///
/// Choreography (designed for "digestible, not flashing"):
///   - All connected rows appear together in a "Reading…" state (spinner).
///   - Rows resolve to a green check one at a time on a gentle stagger.
///   - A minimum on-screen floor (2s) guarantees the moment is perceptible.
///   - The subtitle resolves to a "done — here's what's next" line ~before exit,
///     so the auto-advance feels caused, not abrupt.
///
/// All chrome (window body padding) is supplied by `ConnectorContainer`.
struct AutoConnectStep: View {
    /// What the container resolves: which providers genuinely connected (in plan
    /// order) and whether any other steps still need the user.
    struct Resolution: Equatable {
        var connected: [ProviderId]
        var hasRemaining: Bool
    }

    /// Runs the live probe (on the container, against the real providers) and
    /// returns the resolved set. Called once when the screen appears — the
    /// "Reading…" state honestly covers this async work.
    var resolve: () async -> Resolution

    /// Called exactly once when the screen is done. Passes the connected set so
    /// the container can check off the matching plan steps. An empty array means
    /// nothing connected (the container should fall through to the plan).
    var onFinished: ([ProviderId]) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Timing (ms)

    /// Hold after entrance before the first row resolves — sells "it's working".
    private let preHoldMS: UInt64 = 360
    /// Minimum the screen stays on-screen, regardless of count — the "digestible"
    /// guarantee. Never auto-advances before this.
    private let floorMS: Double = 2000
    /// Minimum dwell after the last row resolves.
    private let minDwellMS: Double = 540

    private func staggerMS(forCount n: Int) -> Double { Self.staggerMS(forCount: n) }

    /// Per-row resolve stagger. Tighter for larger sets so total time stays bounded.
    static func staggerMS(forCount n: Int) -> Double { n >= 4 ? 220 : 300 }

    /// Total on-screen time for a given count: pre-hold + staggers + dwell, where
    /// dwell is padded so the total never drops below the floor. Pure — tested to
    /// guarantee the "digestible, never flashes by" minimum.
    static func totalDurationMS(
        count: Int,
        preHoldMS: Double = 360,
        floorMS: Double = 2000,
        minDwellMS: Double = 540
    ) -> Double {
        let elapsed = preHoldMS + staggerMS(forCount: count) * Double(max(0, count - 1))
        return elapsed + max(minDwellMS, floorMS - elapsed)
    }

    // MARK: - State

    /// One visible row. `connected` flips from spinner → check during the
    /// stagger; `visible` drives the reduce-motion staggered reveal.
    private struct Row: Identifiable, Equatable {
        let id: ProviderId
        let name: String
        let sublabel: String
        var connected: Bool
        var visible: Bool
    }

    @State private var rows: [Row] = []
    @State private var subtitle: String = Self.checkingSubtitle
    @State private var canAdvance = false
    @State private var hasRemaining = true
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Headline + subtitle
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text("Already connected")
                    .font(Tokens.Typography.Onboarding.h2)
                    .foregroundStyle(Tokens.Color.text(scheme))
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(Tokens.Typography.Onboarding.lede)
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeInOut(duration: Tokens.Motion.standard), value: subtitle)
            }

            // Connected rows
            VStack(spacing: Tokens.Spacing.s2) {
                ForEach(rows) { row in
                    connectedRow(row)
                }
            }
            .padding(.top, Tokens.Spacing.s5)

            Spacer(minLength: Tokens.Spacing.s5)

            // Footer — no Back (system-driven, transitional). The trailing button
            // is a passive escape: disabled while checking, enabled at the floor.
            WindowFooter {
                EmptyView()
            } trailing: {
                if canAdvance {
                    Button(hasRemaining ? "Continue" : "Show my usage") {
                        complete()
                    }
                    .buttonStyle(.tokenPrimary)
                    .transition(.opacity)
                } else {
                    Button("One moment…") {}
                        .buttonStyle(.tokenSecondary)
                        .disabled(true)
                        .opacity(0.6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await run() }
    }

    // MARK: - Row

    private func connectedRow(_ row: Row) -> some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.s4 - 2) { // 14pt gap
            statusIcon(connected: row.connected)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(Tokens.Typography.Onboarding.body.weight(.medium))
                    .foregroundStyle(Tokens.Color.text(scheme))
                Text(row.sublabel)
                    .font(.custom("DM Sans", size: 12))
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
            }

            Spacer(minLength: 0)

            Text(row.connected ? "Connected" : "Reading…")
                .font(.custom("DM Sans", size: 12))
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .animation(.easeInOut(duration: Tokens.Motion.standard), value: row.connected)
        }
        .padding(.vertical, Tokens.Spacing.s4)        // 16pt — match DetectStep
        .padding(.horizontal, Tokens.Spacing.s5 - 4)  // 20pt
        .background(Tokens.Color.surface(scheme))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .strokeBorder(Tokens.Color.border(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        .opacity(row.visible ? 1 : 0)
        // VoiceOver: one element per row, not four fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            row.connected
                ? "\(row.name), connected. \(row.sublabel)."
                : "\(row.name), reading credentials."
        )
    }

    /// Fixed 22pt slot — spinner and checkmark occupy the identical space so the
    /// row never reflows. Crossfade (no pop) when resolving.
    @ViewBuilder
    private func statusIcon(connected: Bool) -> some View {
        ZStack {
            CircularSpinner(size: 14, color: Tokens.Color.accent(scheme))
                .opacity(connected ? 0 : 1)

            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tokens.Color.success(scheme))
                .opacity(connected ? 1 : 0)
                .scaleEffect(connected ? 1 : 0.6)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: connected)
    }

    // MARK: - Driver

    @MainActor
    private func run() async {
        let resolution = await resolve()
        hasRemaining = resolution.hasRemaining

        // Nothing connected — pass straight through to the plan. (Rare: the user
        // had CLI tools selected but none were actually signed in.)
        guard !resolution.connected.isEmpty else {
            complete()
            return
        }

        let connected = resolution.connected
        let count = connected.count

        if reduceMotion {
            await runReduceMotion(connected)
        } else {
            await runAnimated(connected)
        }

        // Resolve the subtitle to a "done" line so the advance feels caused.
        withAnimation { subtitle = doneSubtitle(hasRemaining: resolution.hasRemaining) }

        // Announce the outcome once (not per-row — that's audio strobing).
        announce(count: count, hasRemaining: resolution.hasRemaining)

        // Enable the manual escape.
        withAnimation { canAdvance = true }

        // VoiceOver users get no auto-advance — they leave via the focused button.
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return }

        // Auto-advance after the remaining dwell.
        try? await Task.sleep(for: .milliseconds(UInt64(remainingDwellMS(count: count))))
        complete()
    }

    /// Animated path: rows appear together (checking), then resolve staggered.
    @MainActor
    private func runAnimated(_ connected: [ProviderId]) async {
        rows = connected.map { makeRow($0, connected: false, visible: true) }
        try? await Task.sleep(for: .milliseconds(preHoldMS))

        let stagger = staggerMS(forCount: connected.count)
        for index in rows.indices {
            withAnimation { rows[index].connected = true }
            if index < rows.count - 1 {
                try? await Task.sleep(for: .milliseconds(UInt64(stagger)))
            }
        }
    }

    /// Reduce-motion path: no spinner, no movement. Rows appear already-connected,
    /// one at a time via opacity steps, preserving the "one at a time" reading.
    @MainActor
    private func runReduceMotion(_ connected: [ProviderId]) async {
        rows = connected.map { makeRow($0, connected: true, visible: false) }
        try? await Task.sleep(for: .milliseconds(preHoldMS))

        let stagger = staggerMS(forCount: connected.count)
        for index in rows.indices {
            rows[index].visible = true
            if index < rows.count - 1 {
                try? await Task.sleep(for: .milliseconds(UInt64(stagger)))
            }
        }
    }

    /// Dwell remaining after the last row resolves, such that total on-screen
    /// time meets the floor. `elapsed` = preHold + all staggers.
    private func remainingDwellMS(count: Int) -> Double {
        let elapsed = Double(preHoldMS) + staggerMS(forCount: count) * Double(max(0, count - 1))
        return max(minDwellMS, floorMS - elapsed)
    }

    /// Idempotent completion — auto-advance and the manual button both route here.
    @MainActor
    private func complete() {
        guard !finished else { return }
        finished = true
        onFinished(rows.filter(\.connected).map(\.id))
    }

    // MARK: - Copy

    private static let checkingSubtitle = "We read these straight from your Mac — no sign-in needed."

    private func doneSubtitle(hasRemaining: Bool) -> String {
        hasRemaining
            ? "Done. Here's what still needs you →"
            : "All set — every tool you picked is connected."
    }

    private func announce(count: Int, hasRemaining: Bool) {
        let toolWord = count == 1 ? "tool" : "tools"
        var message = "\(count) \(toolWord) connected automatically. No sign-in needed."
        if hasRemaining { message += " A few steps still need you." }
        // Polite announcement so VoiceOver summarizes the result once.
        NSAccessibility.post(
            element: NSApp.mainWindow ?? NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    // MARK: - Row content

    private func makeRow(_ id: ProviderId, connected: Bool, visible: Bool) -> Row {
        let (name, sublabel) = Self.rowContent(for: id)
        return Row(id: id, name: name, sublabel: sublabel, connected: connected, visible: visible)
    }

    /// Provider name + the local source we read from. Names match the plan's
    /// CLI step titles; sublabels name the source to build trust ("we read
    /// something local, not phoning home").
    private static func rowContent(for id: ProviderId) -> (name: String, sublabel: String) {
        switch id {
        case .claude:  return ("Claude Code", "Reading ~/.claude credentials")
        case .codex:   return ("Codex CLI", "Reading ~/.codex credentials")
        case .gemini:  return ("Gemini CLI", "Reading ~/.gemini credentials")
        case .copilot: return ("GitHub Copilot", "Signed in via the gh CLI")
        case .cursor:  return ("Cursor", "Local usage data")
        default:       return (id.poolLabel, "Already connected on your Mac")
        }
    }
}

// MARK: - Preview

#Preview("Auto-connect — 3 connected (light)") {
    AutoConnectStep(
        resolve: { .init(connected: [.claude, .cursor, .copilot], hasRemaining: true) },
        onFinished: { _ in }
    )
    .padding(.top, Tokens.Spacing.s6)
    .padding(.horizontal, 40)
    .padding(.bottom, Tokens.Spacing.s5 + 4)
    .frame(width: 720, height: 560)
    .background(Tokens.DynamicColor.bg)
    .preferredColorScheme(.light)
}

#Preview("Auto-connect — 3 connected (dark)") {
    AutoConnectStep(
        resolve: { .init(connected: [.claude, .cursor, .copilot], hasRemaining: true) },
        onFinished: { _ in }
    )
    .padding(.top, Tokens.Spacing.s6)
    .padding(.horizontal, 40)
    .padding(.bottom, Tokens.Spacing.s5 + 4)
    .frame(width: 720, height: 560)
    .background(Tokens.DynamicColor.bg)
    .preferredColorScheme(.dark)
}

#Preview("Auto-connect — single, nothing remains (light)") {
    AutoConnectStep(
        resolve: { .init(connected: [.claude], hasRemaining: false) },
        onFinished: { _ in }
    )
    .padding(.top, Tokens.Spacing.s6)
    .padding(.horizontal, 40)
    .padding(.bottom, Tokens.Spacing.s5 + 4)
    .frame(width: 720, height: 560)
    .background(Tokens.DynamicColor.bg)
    .preferredColorScheme(.light)
}
