import AppKit
import os

/// Opens the MenuBarExtra popover from code (SwiftUI has no first-party API for it).
///
/// Replaces the MenuBarExtraAccess package, which leaked KVO + window observers
/// on every App-scene re-evaluation — after a few days of uptime, opening the
/// popover fanned out to thousands of them and lagged by over a second. This is
/// a one-shot call with no observers, so there's nothing to accumulate.
///
/// Both paths lean on private AppKit details (the status bar window's
/// `statusItem` key, and the macOS 27 expanded-interface-session SPI), so every
/// step is guarded and failure is a silent no-op — the user can still click.
@MainActor
enum StatusItemPresenter {
    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "StatusItemPresenter")

    private static let beginSession = NSSelectorFromString("_beginExpandedInterfaceSession:")
    private static let delegateSelector = NSSelectorFromString("expandedInterfaceDelegate")

    static func open() {
        guard let statusItem else {
            log.info("Status item not found — skipping programmatic popover open")
            return
        }

        // macOS 27+: SwiftUI no longer wires the button's target/action, so a
        // simulated click does nothing. Presentation goes through an "expanded
        // interface session" instead. The begin call takes the triggering event's
        // timestamp and drops anything older than the last dismissal (a debounce);
        // with no real event, pass the max value so it always passes.
        if statusItem.responds(to: beginSession),
           statusItem.responds(to: delegateSelector),
           statusItem.perform(delegateSelector) != nil,
           let implementation = statusItem.method(for: beginSession) {
            typealias BeginSession = @convention(c) (NSStatusItem, Selector, TimeInterval) -> Void
            unsafeBitCast(implementation, to: BeginSession.self)(statusItem, beginSession, .greatestFiniteMagnitude)
            return
        }

        // macOS 13–26: mimic the user clicking the menu bar item.
        statusItem.button?.performClick(nil)
    }

    /// The status item SwiftUI created for our MenuBarExtra. It isn't exposed
    /// publicly, but it hangs off the private NSStatusBarWindow that hosts it.
    /// Only the main instance is wanted — on multi-display setups the other
    /// windows hold replicas (an NSStatusItem subclass).
    private static var statusItem: NSStatusItem? {
        let mainClassName: String
        if #available(macOS 26.0, *) {
            mainClassName = "NSSceneStatusItem"
        } else {
            mainClassName = "NSStatusItem"
        }

        return NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }
            .first { $0.className == mainClassName }
    }
}
