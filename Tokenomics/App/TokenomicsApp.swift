import AppKit
import SwiftUI
import os

@main
struct TokenomicsApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @StateObject private var updaterService = UpdaterService()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("textSize") private var textSizeRaw: String = TextSize.compact.rawValue

    /// Popover width depends on both provider count (4+ need extra room for
    /// icon-only tabs) and user-selected text size (Medium/Large need wider
    /// popovers to avoid cramping or truncating).
    private var popoverWidth: CGFloat {
        let size = TextSize(rawValue: textSizeRaw) ?? .compact
        return size.popoverWidth(providerCount: viewModel.visibleProviders.count)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel, updaterService: updaterService)
                .frame(width: popoverWidth)
                .onAppear {
                    // Wire the exporter reference once the popover is ready.
                    // This is idempotent — assigning the same actor reference again is harmless.
                    viewModel.macSideStateExporter = appDelegate.macSideStateExporter
                }
        } label: {
            // First-launch routing + polling kickoff live inside MenuBarLabel so
            // the view's environment (openWindow) is available. startPolling()
            // is gated on hasCompletedOnboarding inside the view model.
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        // MARK: - Onboarding Window

        onboardingWindow
    }

    /// Onboarding window with restoration disabled on macOS 15+.
    ///
    /// `@SceneBuilder` doesn't support `if #available`, so the conditional is
    /// applied in a plain function that returns `any Scene`. On macOS 14 the
    /// belt is the `.accessory` activation policy set in `applicationDidFinishLaunching`.
    private var onboardingWindow: some Scene {
        onboardingScene()
    }

    private func onboardingScene() -> some Scene {
        let base = WindowGroup(id: "onboarding") {
            OnboardingWindowRoot(viewModel: viewModel, webCompanion: appDelegate.webCompanionService)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 560)
        .windowStyle(.titleBar)

        if #available(macOS 15.0, *) {
            return base.restorationBehavior(.disabled)
        }
        return base
    }
}

// MARK: - Onboarding window root

/// Wraps ConnectorContainer for the onboarding WindowGroup.
/// Switches NSApplication's activation policy to `.regular` so the window is
/// focusable (LSUIElement is still `true` — no Dock icon except while this view
/// is visible), then restores `.accessory` when it disappears.
struct OnboardingWindowRoot: View {
    @ObservedObject var viewModel: UsageViewModel
    var webCompanion: any WebCompanionStateProvider
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ConnectorContainer(viewModel: viewModel, webCompanion: webCompanion) {
            // Onboarding finished. Close the window and bring the menu bar
            // back into focus so the user can click the Tokenomics icon to
            // see their usage. (SwiftUI's MenuBarExtra doesn't expose a
            // public API to *open* the popover programmatically — the user
            // has to click the icon themselves. Activating the app gives the
            // icon visual focus in case the menu bar was occluded.)
            NSApp.activate(ignoringOtherApps: true)
            dismissWindow(id: "onboarding")
        }
        .frame(width: 720, height: 560)
        .background(Tokens.DynamicColor.bg.ignoresSafeArea())
        .onAppear {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Bridge notification names

extension Notification.Name {
    /// Posted by AppDelegate when the extension requests a native-provider refresh.
    /// Observed by UsageViewModel on the main actor to trigger re-polling.
    static let tokenomicsBridgeRefreshRequested = Notification.Name("tokenomicsBridgeRefreshRequested")

    /// Posted by SettingsService.setVisibility after each provider visibility change.
    /// Object is the ProviderId.rawValue String; userInfo contains the ProviderVisibilitySetting.
    static let tokenomicsProviderVisibilityChanged = Notification.Name("tokenomicsProviderVisibilityChanged")
}

// MARK: - AppDelegate

/// Handles tokenomics:// deep links via NSAppleEventManager instead of .onOpenURL,
/// which fires incorrectly in MenuBarExtra and causes performance issues.
///
/// Also owns the two long-lived bridge services (WebCompanionService and
/// MacSideStateExporter) so they survive across SwiftUI scene reconstructions.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "AppDelegate")

    // MARK: - Bridge Services (app-lifetime singletons)

    /// Watches ext-side.json for incoming web-companion data.
    let webCompanionService = WebCompanionService(onRefreshRequested: {
        // WebCompanionService fires this on an arbitrary actor. Post a notification
        // so UsageViewModel (@MainActor) can pick it up safely on the main queue.
        NotificationCenter.default.post(name: .tokenomicsBridgeRefreshRequested, object: nil)
    })

    /// Writes mac-side.json with native snapshots, settings, and pending commands.
    let macSideStateExporter = MacSideStateExporter()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: ensure we start as a menu-bar agent even if SwiftUI
        // auto-restored an onboarding window from a previous session.
        NSApplication.shared.setActivationPolicy(.accessory)

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        installNMHManifests()
        startBridgeServices()
    }

    // MARK: - NMH Manifest Install

    private func installNMHManifests() {
        do {
            let result = try NMHManifestInstaller.installAll()
            Self.log.info("NMH manifest install: written=\(result.written) unchanged=\(result.unchanged) skipped=\(result.skipped) failed=\(result.failed)")
        } catch {
            // Never crash the app over a manifest install failure.
            // Users without a Chromium browser simply won't get the bridge.
            Self.log.error("NMH manifest install failed: \(error)")
        }
    }

    // MARK: - Bridge Service Startup

    private func startBridgeServices() {
        Task {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            await macSideStateExporter.setMacAppVersion(version)

            // Seed visibility from UserDefaults so the exporter's first write to
            // mac-side.json reflects the user's saved settings immediately.
            let savedVisibility = SettingsService.providerVisibility
            for (key, setting) in savedVisibility {
                await macSideStateExporter.setVisibility(setting, for: key)
            }
        }

        Task {
            await webCompanionService.startWatching()
        }
    }

    // MARK: - URL Handler

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "tokenomics" else { return }

        switch url.host {
        case "share":
            showShareSheet()
        case "open":
            NSApp.activate(ignoringOtherApps: true)
        default:
            break
        }
    }

    private func showShareSheet() {
        let shareURL = URL(string: "https://robrstout.com/work/tokenomics/")!
        let shareText = "Tokenomics — see your AI coding tool usage at a glance. Free and open source."
        let items: [Any] = [shareText, shareURL]

        let picker = NSSharingServicePicker(items: items)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            let view = window.contentView ?? window.contentViewController?.view ?? NSView()
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }
}

// MARK: - MenuBarLabel

/// The menu bar label — shows ring + percentage for one provider.
/// Smart mode picks the worst-of-N; pinned mode shows the user's choice.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            switch viewModel.menuBarState {
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.red)

            case .unauthenticated:
                Image(nsImage: MenuBarRingsRenderer.image(
                    fiveHourFraction: 0,
                    sevenDayFraction: 0,
                    fiveHourPace: 0,
                    sevenDayPace: 0
                ))

            default:
                ringLabel
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.menuBarTooltip)
        .help(viewModel.menuBarTooltip)
        .onAppear {
            // First-launch users go through the guided flow before polling so
            // the keychain / cross-app TCC prompts come from a known UI moment
            // (PermissionsStep) instead of firing blind on app launch.
            if !viewModel.hasCompletedOnboarding {
                openWindow(id: "onboarding")
            }
            // Always-safe call — startPolling no-ops when not yet onboarded.
            viewModel.startPolling()
        }
    }

    // MARK: - Ring + Percentage

    @ViewBuilder
    private var ringLabel: some View {
        if let usage = activeUsage {
            if let longWindow = usage.longWindow {
                Image(nsImage: MenuBarRingsRenderer.image(
                    fiveHourFraction: usage.shortWindow.utilization / 100,
                    sevenDayFraction: longWindow.utilization / 100,
                    fiveHourPace: usage.shortWindow.pace,
                    sevenDayPace: longWindow.pace
                ))
            } else {
                Image(nsImage: MenuBarRingsRenderer.singleRingImage(
                    fraction: usage.shortWindow.utilization / 100,
                    pace: usage.shortWindow.pace
                ))
            }

            Text("\(Int(usage.shortWindow.utilization))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .padding(.leading, 6)
        } else {
            // No snapshot yet (loading or just-connected with no usage data) —
            // show empty rings rather than a bare "—". The renderer always draws
            // the tracks; pace dots are gated on pace > 0 so they're naturally
            // omitted when the window hasn't started elapsing.
            Image(nsImage: MenuBarRingsRenderer.image(
                fiveHourFraction: 0,
                sevenDayFraction: 0,
                fiveHourPace: 0,
                sevenDayPace: 0
            ))

            Text("0%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .padding(.leading, 6)
        }
    }

    /// The usage snapshot to display: pinned provider if set, otherwise worst-of-N.
    private var activeUsage: ProviderUsageSnapshot? {
        if let pinned = viewModel.pinnedProviders.first,
           let usage = viewModel.providerStates[pinned]?.usage {
            return usage
        }
        return viewModel.worstOfNUsage()
    }
}
