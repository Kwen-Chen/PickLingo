import Cocoa
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class AccessibilityMonitor: ObservableObject {
    @Published var selectedText: String = ""
    @Published var selectionOrigin: NSPoint = .zero

    private var pollTimer: Timer?
    private var mouseUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private var keyDownMonitor: Any?
    private var isMouseButtonDown = false
    private var mouseDownPosition: NSPoint = .zero
    private var mouseDownInTextSelectionContext = false
    private var lastSelection: String = ""
    private var lastPollPid: pid_t = 0
    private var lastPollResult: String = ""

    var onTextSelected: ((String, NSPoint) -> Void)?
    var onSelectionCleared: (() -> Void)?

    // Apps where AX API fails — use pasteboard fallback
    private var axFailedApps: Set<pid_t> = []

    // Debounce: avoid firing onTextSelected too rapidly
    private var lastSelectionOrigin: NSPoint = .zero
    private var debounceWorkItem: DispatchWorkItem?
    private var debounceInterval: TimeInterval {
        // Reuse the user-facing tooltip delay setting as the debounce delay.
        max(0.0, min(2.0, AppSettings.shared.tooltipDelay))
    }
    /// Minimum mouse movement (in points) to consider a new selection gesture for the same text.
    private static let positionThreshold: CGFloat = 5
    /// Minimum drag distance (in points) to treat mouse-up as a text-selection gesture.
    private static let selectionGestureThreshold: CGFloat = 3

    private enum AXSelectionProbe {
        case text(String)
        case empty
        case nonTextContext
        case unsupported
    }

    nonisolated var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func startMonitoring() {
        let granted = isAccessibilityGranted
        print("[PickLingo] startMonitoring called, accessibility granted: \(granted)")
        guard granted else {
            requestAccessibility()
            return
        }

        stopMonitoring()

        // Poll AX API — 0.3s is sufficient and lighter on CPU than 0.2s
        // Timer fires on main RunLoop, so the callback is already on the main thread.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSelectionViaAX()
            }
        }
        RunLoop.current.add(pollTimer!, forMode: .common)

        // Track mouse-down to suppress AX poll triggers during drag selection
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isMouseButtonDown = true
                let mousePos = NSEvent.mouseLocation
                self.mouseDownPosition = mousePos

                guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                    self.mouseDownInTextSelectionContext = false
                    return
                }
                if frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                    self.mouseDownInTextSelectionContext = false
                    return
                }
                guard AppSettings.shared.isAppEnabled(bundleID: frontApp.bundleIdentifier) else {
                    self.mouseDownInTextSelectionContext = false
                    return
                }
                self.mouseDownInTextSelectionContext = self.isLikelyTextSelectionContext(
                    pid: frontApp.processIdentifier,
                    at: mousePos
                )
            }
        }

        // Global mouse-up monitor — catches selection end in ALL apps
        // NSEvent global monitors fire on the main thread, but wrap in Task for safety.
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            let mousePos = NSEvent.mouseLocation
            let clickCount = event.clickCount
            // Small delay to let the app update its selection state
            Task { @MainActor [weak self] in
                self?.isMouseButtonDown = false
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                self?.checkSelectionAfterMouseUp(at: mousePos, clickCount: clickCount)
            }
        }

        // Dismiss selection-driven UI immediately when user starts typing over selection.
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalKeyDown(event)
            }
        }

        print("[PickLingo] Monitoring started (AX polling + mouse-up global monitor)")
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        isMouseButtonDown = false
        mouseDownInTextSelectionContext = false
        lastSelection = ""
        lastSelectionOrigin = .zero
        lastPollPid = 0
        lastPollResult = ""
        debounceWorkItem?.cancel()
    }

    // MARK: - AX-based detection (Typora, Notes, TextEdit, etc.)

    private func checkSelectionViaAX() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        if frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        guard AppSettings.shared.isAppEnabled(bundleID: frontApp.bundleIdentifier) else {
            clearSelection()
            return
        }
        let pid = frontApp.processIdentifier

        // Skip apps we know AX fails for — they use the mouse-up method instead
        if axFailedApps.contains(pid) { return }

        switch Self.probeSelectionViaAX(pid: pid) {
        case .text(let text):
            // Quick dedup: if same pid + same text as last poll, skip
            if pid == lastPollPid && text == lastPollResult { return }
            lastPollPid = pid
            lastPollResult = text
            // Don't trigger tooltip during mouse drag — wait for mouse-up
            guard !isMouseButtonDown else { return }
            handleDetectedText(text)
        case .empty:
            // Selection became empty (e.g. user cleared selection via keyboard/delete).
            // Clear immediately so tooltip/result panel are dismissed without waiting for mouse-up.
            lastPollPid = pid
            lastPollResult = ""
            guard !isMouseButtonDown else { return }
            let mousePos = NSEvent.mouseLocation
            // Avoid clearing while the user is interacting with obvious non-text
            // chrome (especially title bar drag), which would otherwise reset
            // dedup state and cause tooltip re-popups.
            guard isLikelyTextSelectionContext(pid: pid, at: mousePos) else { return }
            clearSelection()
        case .nonTextContext:
            // Focus moved to a non-text UI element (e.g. list/file item, title bar).
            // Ignore it so we don't treat non-text selections as translatable text.
            return
        case .unsupported:
            // Some apps temporarily expose non-text focused elements during
            // title-bar/toolbar interactions. Don't permanently mark AX as failed
            // for the whole app in that transient non-text context.
            let mousePos = NSEvent.mouseLocation
            if isLikelyTextSelectionContext(pid: pid, at: mousePos) {
                axFailedApps.insert(pid)
            }
            return
        }
    }

    nonisolated private static func axAttributeString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &ref)
        guard status == .success else { return nil }
        return ref as? String
    }

    nonisolated private static func isSemanticTextElement(_ element: AXUIElement, role: String?, subrole: String?) -> Bool {
        let textRoles: Set<String> = [
            "AXTextArea",
            "AXTextField",
            "AXWebArea",
            "AXComboBox",
            "AXDocument",
        ]
        let textSubroles: Set<String> = [
            "AXSearchField",
        ]
        if let role, textRoles.contains(role) { return true }
        if let subrole, textSubroles.contains(subrole) { return true }

        // Generic fallback: many genuine text containers expose selected text range.
        var selectedRangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeRef
        )
        return rangeStatus == .success
    }

    /// Pure function — no mutable state access; safe to call from anywhere.
    nonisolated private static func probeSelectionViaAX(pid: pid_t) -> AXSelectionProbe {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedElementRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusResult == .success, let focusedElement = focusedElementRef else {
            return .unsupported
        }

        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return .unsupported
        }
        let element = unsafeBitCast(focusedElement, to: AXUIElement.self)
        let role = axAttributeString(element, kAXRoleAttribute as CFString)
        let subrole = axAttributeString(element, kAXSubroleAttribute as CFString)
        guard isSemanticTextElement(element, role: role, subrole: subrole) else {
            return .nonTextContext
        }

        var selectedTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )

        guard textResult == .success else { return .unsupported }
        let text = (selectedTextRef as? String) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .empty
        }
        return .text(text)
    }

    // MARK: - Mouse-up based detection (Chrome, VS Code, etc.)

    private func checkSelectionAfterMouseUp(at mousePos: NSPoint, clickCount: Int) {
        let startedInTextContext = mouseDownInTextSelectionContext
        mouseDownInTextSelectionContext = false

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        if frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        guard AppSettings.shared.isAppEnabled(bundleID: frontApp.bundleIdentifier) else {
            clearSelection()
            return
        }
        let pid = frontApp.processIdentifier

        let dx = mousePos.x - mouseDownPosition.x
        let dy = mousePos.y - mouseDownPosition.y
        let dragDistance = sqrt(dx * dx + dy * dy)
        // Single click with nearly no movement is usually just caret placement.
        let isLikelySelectionGesture = dragDistance > Self.selectionGestureThreshold || clickCount >= 2
        let isTextSelectionContext = isLikelyTextSelectionContext(pid: pid, at: mousePos)

        // First try AX API
        switch Self.probeSelectionViaAX(pid: pid) {
        case .text(let text):
            // Ignore obvious non-text chrome interactions (e.g. title-bar drag).
            // Keep the current selection state so AX polling doesn't retrigger
            // the same tooltip while the user is moving the window around.
            guard startedInTextContext, isTextSelectionContext else {
                return
            }
            guard isLikelySelectionGesture else {
                clearSelection()
                return
            }
            handleDetectedText(text, at: mousePos, allowRepeatForSameText: true)
            return
        case .empty:
            clearSelection()
            return
        case .nonTextContext:
            return
        case .unsupported:
            break
        }

        // Fallback: simulate Cmd+C and read pasteboard
        // Only for apps where AX failed, and only when gesture likely selected text.
        if axFailedApps.contains(pid) {
            guard startedInTextContext, isTextSelectionContext else {
                return
            }
            guard isLikelySelectionGesture else {
                clearSelection()
                return
            }
            getSelectedTextViaPasteboard { [weak self] text in
                guard let self else { return }
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.handleDetectedText(text, at: mousePos, allowRepeatForSameText: true)
                } else {
                    // No text selected after mouse-up — selection was cleared
                    self.clearSelection()
                }
            }
            return
        }

        // AX returned empty/no selection — clear
        clearSelection()
    }

    /// Best-effort guard to avoid copy-fallback false positives from non-text UI areas
    /// (e.g. title bar double-click, toolbar clicks).
    private func isLikelyTextSelectionContext(pid: pid_t, at point: NSPoint) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)

        var hitRef: AXUIElement?
        let hitStatus = AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &hitRef)
        guard hitStatus == .success, let hitElement = hitRef else {
            // If we cannot determine the role, keep old behavior to avoid regressions.
            return true
        }

        func attributeString(_ element: AXUIElement, _ attribute: CFString) -> String? {
            var ref: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, attribute, &ref)
            guard status == .success else { return nil }
            return ref as? String
        }

        func parentElement(of element: AXUIElement) -> AXUIElement? {
            var ref: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref)
            guard status == .success, let parent = ref else { return nil }
            guard CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(parent, to: AXUIElement.self)
        }

        // Explicitly reject obvious non-text chrome areas. Check both role and
        // subrole across a small parent chain to catch cases where hit-testing
        // returns a nested AXGroup inside the title bar/toolbar.
        let blockedRoles: Set<String> = [
            kAXWindowRole as String,
            "AXTitleBar",
            kAXToolbarRole as String,
            kAXButtonRole as String,
            kAXMenuBarRole as String,
            kAXMenuBarItemRole as String,
            kAXMenuRole as String,
            kAXMenuItemRole as String,
        ]
        let blockedSubroles: Set<String> = [
            "AXTitleBar",
        ]

        var current: AXUIElement? = hitElement
        var depth = 0
        while let element = current, depth < 6 {
            if let role = attributeString(element, kAXRoleAttribute as CFString), blockedRoles.contains(role) {
                return false
            }
            if let subrole = attributeString(element, kAXSubroleAttribute as CFString), blockedSubroles.contains(subrole) {
                return false
            }
            current = parentElement(of: element)
            depth += 1
        }
        return true
    }

    private func getSelectedTextViaPasteboard(completion: @escaping @MainActor (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: false)
        cmdUp?.flags = .maskCommand
        cmdUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let newText: String?
            if pasteboard.changeCount != previousChangeCount {
                newText = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                if let prev = previousContents {
                    pasteboard.setString(prev, forType: .string)
                }
            } else {
                newText = nil
            }
            completion(newText)
        }
    }

    // MARK: - Common handler (debounced)

    private func handleDetectedText(
        _ text: String,
        at position: NSPoint? = nil,
        allowRepeatForSameText: Bool = false
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let origin = position ?? NSEvent.mouseLocation

        // Allow re-trigger for the same text if the mouse position moved significantly
        // (indicates a new selection gesture, e.g. re-selecting the same word).
        if trimmed == lastSelection {
            guard allowRepeatForSameText else { return }
            let dx = origin.x - lastSelectionOrigin.x
            let dy = origin.y - lastSelectionOrigin.y
            let distance = sqrt(dx * dx + dy * dy)
            guard distance > Self.positionThreshold else { return }
        }

        lastSelection = trimmed
        lastSelectionOrigin = origin

        // Debounce: cancel previous pending callback, schedule new one
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.selectedText = trimmed
            self.selectionOrigin = origin
            self.onTextSelected?(trimmed, origin)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    func clearSelection() {
        if !lastSelection.isEmpty {
            lastSelection = ""
            lastSelectionOrigin = .zero
            lastPollPid = 0
            lastPollResult = ""
            debounceWorkItem?.cancel()
            selectedText = ""
            onSelectionCleared?()
        }
    }

    private func handleGlobalKeyDown(_ event: NSEvent) {
        guard !lastSelection.isEmpty else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        if frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }

        // Only treat likely text-editing key presses as selection-clearing actions.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasBlockingModifiers = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        guard !hasBlockingModifiers else { return }

        clearSelection()
    }
}
