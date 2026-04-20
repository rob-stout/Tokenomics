import AppKit
import SwiftUI

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
        } label: {
            MenuBarLabel(viewModel: viewModel)
                .onAppear {
                    viewModel.startPolling()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Handles tokenomics:// deep links via NSAppleEventManager instead of .onOpenURL,
/// which fires incorrectly in MenuBarExtra and causes performance issues.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

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

/// The menu bar label — shows ring + percentage for one provider.
/// Smart mode picks the worst-of-N; pinned mode shows the user's choice.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 0) {
            switch viewModel.menuBarState {
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.red)

            case .unauthenticated:
                Image(systemName: "person.crop.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.secondary)

            default:
                ringLabel
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.menuBarTooltip)
        .help(viewModel.menuBarTooltip)
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
            Text("—")
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
