import Cocoa

/// A nonactivating panel can receive a click while another app remains frontmost
/// and Quartz still reports that app as the target. Keep its whole click local.
struct SelectionEventRouting {
    private var leftMouseDownWasLocal = false

    static func isPointerEvent(_ type: NSEvent.EventType) -> Bool {
        [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(type)
    }

    mutating func shouldForward(_ type: NSEvent.EventType, targetIsOwnApp: Bool,
                               frontmostIsOwnApp: Bool, hitsOwnWindow: Bool) -> Bool {
        let local = targetIsOwnApp || frontmostIsOwnApp || (Self.isPointerEvent(type) && hitsOwnWindow)
        if type == .leftMouseDown { leftMouseDownWasLocal = local }
        if type == .leftMouseUp {
            let startedLocally = leftMouseDownWasLocal
            leftMouseDownWasLocal = false
            if startedLocally { return false }
        }
        return !local
    }
}

/// Own the passive tap so its real health is observable. NSEvent's opaque global
/// monitor token can outlive its underlying event delivery after app transitions.
@MainActor
final class SelectionEventMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var routing = SelectionEventRouting()
    var onEvent: ((NSEvent) -> Void)?
    var onRecovery: (() -> Void)?

    var isHealthy: Bool {
        guard let tap, let source else { return false }
        return CFMachPortIsValid(tap) && CFRunLoopSourceIsValid(source) && CGEvent.tapIsEnabled(tap: tap)
    }

    func start() -> Bool {
        stop()
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown,
                                   .otherMouseDown, .scrollWheel, .keyDown, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<SelectionEventMonitor>.fromOpaque(context).takeUnretainedValue()
                // The source is installed exclusively on the main run loop.
                MainActor.assumeIsolated { monitor.receive(type: type, event: event) }
                // A listen-only tap cannot suppress or modify the original event.
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return isHealthy
    }

    private func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            onRecovery?()
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let nativeEvent = NSEvent(cgEvent: event) else { return }
        let hitsOwnWindow = SelectionEventRouting.isPointerEvent(nativeEvent.type)
            && ownsWindow(at: ScreenLocator.appKitPoint(for: event.location))
        // Checking just the target PID/front app closes our nonactivating toolbar
        // on mouseDown, before SwiftUI can invoke its button on mouseUp.
        guard routing.shouldForward(
            nativeEvent.type,
            targetIsOwnApp: event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(ownPID),
            frontmostIsOwnApp: NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID,
            hitsOwnWindow: hitsOwnWindow
        ) else { return }
        onEvent?(nativeEvent)
    }

    private func ownsWindow(at point: NSPoint) -> Bool {
        // Query the actual top window, not every window whose frame contains the
        // point: a covered settings window must not block selection in another app.
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        return NSApp.windows.contains {
            $0.windowNumber == number && $0.isVisible && $0.alphaValue > 0 && !$0.ignoresMouseEvents
        }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        routing = SelectionEventRouting()
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }
}
