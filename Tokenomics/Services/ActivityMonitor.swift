import Foundation
import CoreServices

/// Watches ~/.claude recursively for file system activity using FSEvents.
/// Detects when Claude Code is actively in use (conversation writes happen
/// deep in ~/.claude/projects/<hash>/), so polling can sleep when idle
/// and wake immediately on activity.
final class ActivityMonitor: @unchecked Sendable {

    private var stream: FSEventStreamRef?
    private let path: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.tokenomics.activity-monitor", qos: .utility)

    /// Box to safely pass the callback through FSEvents' C callback context.
    private final class CallbackBox {
        let handler: @Sendable () -> Void
        init(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }
    }
    private var retainedBox: Unmanaged<CallbackBox>?

    init(path: String = "\(NSHomeDirectory())/.claude", onChange: @escaping @Sendable () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        guard stream == nil else { return }

        let box = CallbackBox(onChange)
        let boxUnmanaged = Unmanaged.passRetained(box)
        retainedBox = boxUnmanaged

        var context = FSEventStreamContext(
            version: 0,
            info: boxUnmanaged.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue().handler()
        }

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [path] as CFArray,
            FSEventsGetCurrentEventId(),
            5.0, // Coalesce events within 5-second windows
            UInt32(kFSEventStreamCreateFlagNoDefer)
        ) else {
            boxUnmanaged.release()
            retainedBox = nil
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if let box = retainedBox {
            box.release()
            retainedBox = nil
        }
    }
}
