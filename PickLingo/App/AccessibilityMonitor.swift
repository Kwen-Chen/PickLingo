import Cocoa
import ApplicationServices
import OSLog

enum SelectionMonitoringState: String {
    case disabled, permissionRequired, active, unavailable
}

/// Reconcile permission and enablement independently of any settings/onboarding window.
@MainActor
final class SelectionMonitoringLifecycle {
    private(set) var state: SelectionMonitoringState = .disabled
    private var registered = false
    private let install: () -> Bool
    private let remove: () -> Void
    private let isHealthy: () -> Bool
    private let stateChanged: (SelectionMonitoringState) -> Void

    init(install: @escaping () -> Bool, remove: @escaping () -> Void,
         isHealthy: @escaping () -> Bool = { true },
         stateChanged: @escaping (SelectionMonitoringState) -> Void = { _ in }) {
        self.install = install
        self.remove = remove
        self.isHealthy = isHealthy
        self.stateChanged = stateChanged
    }

    func reconcile(enabled: Bool, trusted: Bool, restart: Bool = false) {
        guard enabled, trusted else {
            if registered { remove(); registered = false }
            setState(enabled ? .permissionRequired : .disabled)
            return
        }
        if registered, restart || !isHealthy() { remove(); registered = false }
        if !registered {
            registered = install()
            if !registered { remove() } // Clean up partially registered monitors.
        }
        setState(registered ? .active : .unavailable)
    }

    private func setState(_ newState: SelectionMonitoringState) {
        guard state != newState else { return }
        state = newState
        stateChanged(newState)
    }
}

/// Selection detection never sends keys, edits text, or touches the clipboard.
@MainActor
final class AccessibilityMonitor: ObservableObject {
    static let shared = AccessibilityMonitor()
    static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("PickLingoSettings")
    @Published private(set) var monitoringState: SelectionMonitoringState = .disabled
    @Published private(set) var selectedText = ""
    private(set) var selectionBounds: NSRect?
    @Published private(set) var selectionOrigin: NSPoint = .zero

    var onTextSelected: ((String, NSPoint) -> Void)?
    var onSelectionCleared: (() -> Void)?
    var onGlobalKeyEvent: ((NSEvent) -> Void)?

    private var monitors: [Any] = []
    private let globalEvents = SelectionEventMonitor()
    private let delivery = SelectionDelivery()
    private var isMonitoring = false
    private var mouseDown: (point: NSPoint, pid: pid_t)?
    private var monitoringRequested = false
    private var permissionWatchTask: Task<Void, Never>?
    private var workspaceObservers: [Any] = []
    private let logger = Logger(subsystem: "com.picklingo.app", category: "SelectionMonitoring")
    private lazy var lifecycle = SelectionMonitoringLifecycle(
        install: { [weak self] in self?.installEventMonitors() ?? false },
        remove: { [weak self] in self?.removeEventMonitors() },
        isHealthy: { [weak self] in self?.globalEvents.isHealthy == true },
        stateChanged: { [weak self] state in
            guard let self else { return }
            self.monitoringState = state
            self.logger.notice("Selection monitoring state: \(state.rawValue, privacy: .public)")
        }
    )

    nonisolated var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func startMonitoring(restart: Bool = false) {
        monitoringRequested = true
        if permissionWatchTask == nil {
            // This checks our own permission only, never polls other apps' AX trees.
            // It remains alive if onboarding is dismissed before permission is granted.
            permissionWatchTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self else { return }
                    self.refreshMonitoring()
                }
            }
            for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
                workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshMonitoring(restart: true) }
                })
            }
        }
        refreshMonitoring(restart: restart)
    }

    func refreshMonitoring(restart: Bool = false) {
        if monitoringState == .active, !globalEvents.isHealthy {
            logger.notice("Selection event tap is unhealthy; rebuilding listeners")
        }
        lifecycle.reconcile(enabled: monitoringRequested && AppSettings.shared.isEnabled,
                            trusted: isAccessibilityGranted, restart: restart)
    }

    private func installEventMonitors() -> Bool {
        isMonitoring = true
        prepareActiveApplication()

        globalEvents.onEvent = { [weak self] in self?.handleGlobalEvent($0) }
        globalEvents.onRecovery = { [weak self] in
            self?.clearSelection()
            self?.logger.notice("Selection event tap interrupted; requested recovery")
        }
        guard globalEvents.start() else { return false }
        if let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown],
            handler: { [weak self] event in
                self?.handleSettingsEvent(event)
                return event // Always deliver the original event, including Cmd+C / Cmd+V.
            }
        ) {
            monitors.append(localMonitor)
        }
        return monitors.count == 1 && globalEvents.isHealthy
    }

    private func handleGlobalEvent(_ event: NSEvent) {
        // Handle in order on the main run loop; keys invalidate pending reads
        // before any asynchronous AX reply can display stale selection UI.
        switch event.type {
        case .leftMouseDown:
            logger.debug("Selection mouse down received")
            clearSelection()
            guard let app = eligibleApp else { return }
            mouseDown = (event.locationInWindow, app.processIdentifier)
            AXSelectionReader.prepare(pid: app.processIdentifier)
        case .leftMouseUp:
            logger.debug("Selection mouse up received")
            guard let down = mouseDown else { return }
            mouseDown = nil
            guard let app = eligibleApp, down.pid == app.processIdentifier else { return }
            let point = event.locationInWindow
            guard SelectionSession.isSelectionGesture(
                from: down.point, to: point, clickCount: event.clickCount,
                shiftPressed: event.modifierFlags.contains(.shift)
            ) else { return }
            logger.debug("Selection gesture received for process \(down.pid)")
            readSelection(pid: down.pid, at: point)
        case .keyDown:
            clearSelection()
            onGlobalKeyEvent?(event)
        case .flagsChanged:
            onGlobalKeyEvent?(event)
        default:
            clearSelection()
        }
    }

    private func handleSettingsEvent(_ event: NSEvent) {
        guard let window = event.window, window.identifier == Self.settingsWindowIdentifier,
              isMonitoring, AppSettings.shared.isEnabled else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let point = window.convertPoint(toScreen: event.locationInWindow)
        switch event.type {
        case .leftMouseDown:
            clearSelection()
            mouseDown = (point, pid)
        case .leftMouseUp:
            guard let down = mouseDown, down.pid == pid else { return }
            mouseDown = nil
            guard SelectionSession.isSelectionGesture(from: down.point, to: point,
                                                       clickCount: event.clickCount,
                                                       shiftPressed: event.modifierFlags.contains(.shift)) else { return }
            logger.debug("Selection gesture received in settings")
            // The scheduled read runs after the native control handles mouseUp.
            readSelection(pid: pid, at: point)
        default:
            clearSelection()
        }
    }

    func finishSettingsMouseTracking(_ event: NSEvent, in window: NSWindow) {
        // NSTextView / SwiftUI selectable text can consume mouseUp inside their
        // mouseDown tracking loop, bypassing NSEvent's local mouseUp monitor.
        guard window.identifier == Self.settingsWindowIdentifier,
              event.type == .leftMouseDown, NSEvent.pressedMouseButtons & 1 == 0,
              let down = mouseDown, down.pid == ProcessInfo.processInfo.processIdentifier else { return }
        mouseDown = nil
        let point = NSEvent.mouseLocation
        guard SelectionSession.isSelectionGesture(from: down.point, to: point,
                                                   clickCount: event.clickCount,
                                                   shiftPressed: event.modifierFlags.contains(.shift)) else { return }
        logger.debug("Selection tracking completed in settings")
        readSelection(pid: down.pid, at: point)
    }

    func stopMonitoring() {
        monitoringRequested = false
        permissionWatchTask?.cancel()
        permissionWatchTask = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        lifecycle.reconcile(enabled: false, trusted: isAccessibilityGranted)
    }

    private func removeEventMonitors() {
        isMonitoring = false
        globalEvents.stop()
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
              AppSettings.shared.isAppEnabled(bundleID: app.bundleIdentifier) else { return nil }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           NSApp.keyWindow?.identifier != Self.settingsWindowIdentifier { return nil }
        return app
    }

    private func readSelection(pid: pid_t, at point: NSPoint) {
        delivery.schedule(
            pid: pid, at: ScreenLocator.accessibilityPoint(for: point),
            delay: max(0.05, min(2, AppSettings.shared.tooltipDelay)),
            frontmostPID: { [weak self] in self?.eligibleApp?.processIdentifier },
            read: { pid, point in await AXSelectionReader.selection(pid: pid, at: point) },
            onNoSelection: { [weak self] in
                self?.logger.notice("Selection gesture had no accessible text after retry; process \(pid)")
            }
        ) { [weak self] selection in
            guard let self else { return }
            let text = selection.text
            self.selectionBounds = selection.accessibilityBounds.map { ScreenLocator.appKitRect(for: $0) }
            self.logger.debug("Selection read completed; character count: \(text.count)")
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
        selectionBounds = nil
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
        read: @escaping @Sendable (pid_t, CGPoint) async -> SelectionSnapshot?,
        onNoSelection: @escaping () -> Void = {},
        onText: @escaping (SelectionSnapshot) -> Void
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
                    if let text, !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onText(text)
                        return
                    }
                    if attempt == 0 { try await Task.sleep(for: .milliseconds(150)) }
                }
                onNoSelection()
            } catch { /* Superseded by another gesture, key, app switch, or disable. */ }
        }
    }

    func cancel() {
        session.invalidate()
        task?.cancel()
        task = nil
    }
}
