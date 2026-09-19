import Cocoa
import ApplicationServices

struct SelectionSnapshot: Sendable {
    let text: String
    var accessibilityBounds: CGRect? = nil
}

enum SelectionTargetPolicy {
    static let controlRoles: Set<String> = [
        kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXRadioGroupRole,
        kAXPopUpButtonRole, kAXMenuButtonRole, kAXComboBoxRole,
        kAXMenuRole, kAXMenuBarRole, kAXMenuBarItemRole, kAXMenuItemRole,
        kAXToolbarRole, kAXScrollBarRole, kAXSliderRole, kAXIncrementorRole
    ]

    static func allowsSettingsSelection(rolePath: [String]) -> Bool {
        guard let hit = rolePath.first,
              [kAXStaticTextRole, kAXTextFieldRole, kAXTextAreaRole].contains(hit) else { return false }
        // A radio/checkbox label is text, but belongs to its interactive control.
        return rolePath.allSatisfy { !controlRoles.contains($0) }
    }
}

/// AX calls may block when another app is busy. Keep IPC off the event/UI thread,
/// serialize requests, and bound both the messaging timeout and traversal budget.
enum AXSelectionReader {
    private static let queue = DispatchQueue(label: "com.picklingo.selection", qos: .userInitiated)
    // Accessed only on queue. A short debounce coalesces activation and mouse-down;
    // never cache a failure for the lifetime of an app.
    private static var preparedAt: [pid_t: TimeInterval] = [:]

    static func prepare(pid: pid_t) {
        queue.async {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - (preparedAt[pid] ?? -.infinity) > 2 else { return }
            preparedAt = preparedAt.filter { now - $0.value < 60 }
            preparedAt[pid] = now
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            // Chromium/Electron construct their accessibility trees lazily. Ask
            // through supported AX capabilities, without maintaining an app whitelist.
            // Electron may acknowledge AXManualAccessibility without enabling its
            // editor, so also request AXEnhancedUserInterface where supported.
            for name in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
                var settable: DarwinBoolean = false
                guard AXUIElementIsAttributeSettable(app, name as CFString, &settable) == .success,
                      settable.boolValue else { continue }
                var current: CFTypeRef?
                AXUIElementCopyAttributeValue(app, name as CFString, &current)
                guard (current as? NSNumber)?.boolValue != true else { continue }
                AXUIElementSetAttributeValue(app, name as CFString, kCFBooleanTrue)
            }
        }
    }

    static func selectedText(pid: pid_t, at point: CGPoint) async -> String? {
        await selection(pid: pid, at: point)?.text
    }

    static func selection(pid: pid_t, at point: CGPoint) async -> SelectionSnapshot? {
        let operation = ReadOperation()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: operation.read(pid: pid, at: point)) }
            }
        } onCancel: {
            operation.cancel()
        }
    }
}

private final class ReadOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false
    // Accessed only on AXSelectionReader's serial queue.
    private var deadline: TimeInterval = .infinity

    func cancel() {
        lock.lock()
        canceled = true
        lock.unlock()
    }

    private var canRead: Bool {
        lock.lock()
        let canceled = canceled
        lock.unlock()
        return !canceled && ProcessInfo.processInfo.systemUptime < deadline
    }

    func read(pid: pid_t, at point: CGPoint) -> SelectionSnapshot? {
        guard canRead else { return nil }
        deadline = ProcessInfo.processInfo.systemUptime + 0.35
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        let focused = elementAttribute(app, kAXFocusedUIElementAttribute)
        // Never read secure fields, even if an app happens to expose text attributes.
        if let focused, isSecure(focused) { return nil }

        var hit: AXUIElement?
        guard canRead else { return nil }
        AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit)
        if let hit {
            if isSecure(hit) { return nil }
            if let role = attribute(hit, kAXRoleAttribute) as? String,
               nonTextRoles.contains(role) { return nil }
        }

        if pid == ProcessInfo.processInfo.processIdentifier {
            // Settings must only use text under this gesture. A control click
            // must never fall back to a previous selection in the focused field.
            var ancestors: [AXUIElement] = []
            var rolePath: [String] = []
            var current = hit
            while let element = current, ancestors.count < 12, canRead {
                guard !ancestors.contains(where: { CFEqual($0, element) }), !isSecure(element) else { return nil }
                let role = attribute(element, kAXRoleAttribute) as? String ?? ""
                if role == kAXWindowRole { break }
                ancestors.append(element)
                rolePath.append(role)
                current = elementAttribute(element, kAXParentAttribute)
            }
            guard SelectionTargetPolicy.allowsSettingsSelection(rolePath: rolePath) else { return nil }
            for element in ancestors {
                if let selection = snapshot(in: element) { return selection }
            }
            return nil
        }

        // Hit text may live below the focused web area; inspect a few ancestors as well.
        // No permanent app-level failure cache: different controls expose different AX APIs.
        var candidates: [AXUIElement] = [hit, focused].compactMap { $0 }
        var visited: [AXUIElement] = []
        while !candidates.isEmpty, visited.count < 8,
              canRead {
            let element = candidates.removeFirst()
            guard !visited.contains(where: { CFEqual($0, element) }), !isSecure(element) else { continue }
            visited.append(element)
            if let selection = snapshot(in: element) { return selection }
            if let parent = elementAttribute(element, kAXParentAttribute) { candidates.append(parent) }
        }
        return nil
    }

    private let nonTextRoles: Set<String> = SelectionTargetPolicy.controlRoles.union([
        kAXWindowRole, kAXCloseButtonSubrole,
        kAXMinimizeButtonSubrole, kAXZoomButtonSubrole
    ])

    private func snapshot(in element: AXUIElement) -> SelectionSnapshot? {
        guard let text = selectedText(in: element), !text.isEmpty else { return nil }
        var snapshot = SelectionSnapshot(text: text)
        // Geometry is optional: lack of bounds must never break text detection.
        guard canRead, let range = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(range) == AXValueGetTypeID(),
              AXValueGetType(unsafeBitCast(range, to: AXValue.self)) == .cfRange else { return snapshot }
        var value: CFTypeRef?
        guard canRead,
              AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                        range, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return snapshot }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var rect = CGRect.zero
        if AXValueGetType(axValue) == .cgRect, AXValueGetValue(axValue, .cgRect, &rect),
           !rect.isEmpty, !rect.isNull, !rect.isInfinite,
           [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) {
            snapshot.accessibilityBounds = rect
        }
        return snapshot
    }

    private func selectedText(in element: AXUIElement) -> String? {
        if let text = attribute(element, kAXSelectedTextAttribute) as? String, !text.isEmpty { return text }
        // Some editors expose a selected range but no AXSelectedText.
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let rangeValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(rangeValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.location >= 0,
              range.length > 0, range.length <= 100_000 else { return nil }
        guard canRead else { return nil }
        var result: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &result
        ) == .success, let text = result as? String { return text }
        return nil
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole ||
        attribute(element, kAXIdentifierAttribute) as? String == "PickLingoSensitiveField"
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard canRead else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.08)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
