import Cocoa
import ApplicationServices

/// Selection detection never sends keys, edits text, or touches the clipboard.
@MainActor
final class AccessibilityMonitor: ObservableObject {
    @Published private(set) var selectedText = ""
    @Published private(set) var selectionOrigin: NSPoint = .zero

    var onTextSelected: ((String, NSPoint) -> Void)?
    var onSelectionCleared: (() -> Void)?

    private var monitors: [Any] = []
    private let delivery = SelectionDelivery()
    private var isMonitoring = false
    private var mouseDown: (point: NSPoint, pid: pid_t)?

    nonisolated var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func startMonitoring() {
        stopMonitoring()
        guard AppSettings.shared.isEnabled, isAccessibilityGranted else { return }
        isMonitoring = true
        prepareActiveApplication()

        // NSEvent monitor callbacks run on the main thread. Handle them synchronously
        // so a later key/click cannot race a queued Task from an earlier mouse-up.
        addMonitor(for: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            self.clearSelection()
            guard let app = self.eligibleApp else { return }
            self.mouseDown = (NSEvent.mouseLocation, app.processIdentifier)
            AXSelectionReader.prepare(pid: app.processIdentifier)
        }
        addMonitor(for: .leftMouseUp) { [weak self] event in
            guard let self, let down = self.mouseDown else { return }
            self.mouseDown = nil
            guard let app = self.eligibleApp, down.pid == app.processIdentifier else { return }
            let point = NSEvent.mouseLocation
            guard SelectionSession.isSelectionGesture(
                from: down.point, to: point, clickCount: event.clickCount,
                shiftPressed: event.modifierFlags.contains(.shift)
            ) else { return }
            self.readSelection(pid: down.pid, at: point)
        }
        addMonitor(for: [.rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] _ in
            self?.clearSelection()
        }
        addMonitor(for: .keyDown) { [weak self] _ in
            // Includes Cmd+C / Cmd+V: dismiss pending UI and let the app handle the key.
            self?.clearSelection()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        clearSelection()
    }

    func prepareActiveApplication() {
        guard let app = eligibleApp else { return }
        AXSelectionReader.prepare(pid: app.processIdentifier)
    }

    private var eligibleApp: NSRunningApplication? {
        guard isMonitoring, AppSettings.shared.isEnabled,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              AppSettings.shared.isAppEnabled(bundleID: app.bundleIdentifier) else { return nil }
        return app
    }

    private func addMonitor(for mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(monitor)
        }
    }

    private func readSelection(pid: pid_t, at point: NSPoint) {
        delivery.schedule(
            pid: pid, at: ScreenLocator.accessibilityPoint(for: point),
            delay: max(0.05, min(2, AppSettings.shared.tooltipDelay)),
            frontmostPID: { [weak self] in self?.eligibleApp?.processIdentifier },
            read: { pid, point in await AXSelectionReader.selectedText(pid: pid, at: point) }
        ) { [weak self] text in
            guard let self else { return }
            self.selectedText = text
            self.selectionOrigin = point
            self.onTextSelected?(text, point)
        }
    }

    func clearSelection() {
        delivery.cancel()
        mouseDown = nil
        let hadSelection = !selectedText.isEmpty
        selectedText = ""
        selectionOrigin = .zero
        if hadSelection { onSelectionCleared?() }
    }
}

/// A generation is invalidated even before text arrives, so canceled AX replies cannot show UI.
struct SelectionSession {
    struct Request: Equatable {
        let generation: UInt64
        let pid: pid_t
    }

    private var generation: UInt64 = 0

    mutating func invalidate() { generation &+= 1 }

    mutating func begin(pid: pid_t) -> Request {
        invalidate()
        return Request(generation: generation, pid: pid)
    }

    func isCurrent(_ request: Request, frontmostPID: pid_t?) -> Bool {
        request.generation == generation && request.pid == frontmostPID
    }

    static func isSelectionGesture(from start: NSPoint, to end: NSPoint, clickCount: Int, shiftPressed: Bool) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > 3 || clickCount >= 2 || shiftPressed
    }
}

/// Coordinates cancellable reads separately from global event registration.
@MainActor
final class SelectionDelivery {
    private var task: Task<Void, Never>?
    private var session = SelectionSession()

    func schedule(
        pid: pid_t, at point: CGPoint, delay: TimeInterval,
        frontmostPID: @escaping () -> pid_t?,
        read: @escaping @Sendable (pid_t, CGPoint) async -> String?,
        onText: @escaping (String) -> Void
    ) {
        cancel()
        let request = session.begin(pid: pid)
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
                guard let self, self.session.isCurrent(request, frontmostPID: frontmostPID()) else { return }
                // Chromium may still be publishing its AX tree on the first
                // selection after activation. Retry once without requiring a
                // second gesture, and keep every attempt tied to this session.
                for attempt in 0..<2 {
                    try Task.checkCancellation()
                    guard self.session.isCurrent(request, frontmostPID: frontmostPID()) else { return }
                    let text = await read(pid, point)
                    try Task.checkCancellation()
                    guard self.session.isCurrent(request, frontmostPID: frontmostPID()) else { return }
                    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onText(text)
                        return
                    }
                    if attempt == 0 { try await Task.sleep(for: .milliseconds(150)) }
                }
            } catch { /* Superseded by another gesture, key, app switch, or disable. */ }
        }
    }

    func cancel() {
        session.invalidate()
        task?.cancel()
        task = nil
    }
}
