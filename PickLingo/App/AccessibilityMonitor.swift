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
    private var mouseDownWasTextSelectionContext = false
    private var mouseDownContextRole: String?
    private var mouseDownSelectionSnapshot: String = ""
    private var lastMouseUpPoint: NSPoint = .zero
    private var lastMouseUpAt: TimeInterval = 0
    private var lastSelection: String = ""
    private var lastSelectionAt: TimeInterval = 0
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
    private var debugLogsEnabled: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    private func debugLog(_ message: String) {
        guard debugLogsEnabled else { return }
        print("[PickLingo][DBG][Selection] \(message)")
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
                self?.isMouseButtonDown = true
                self?.mouseDownPosition = NSEvent.mouseLocation
                if let self, let frontApp = NSWorkspace.shared.frontmostApplication {
                    let snapshot = Self.getSelectedTextViaAX(pid: frontApp.processIdentifier) ?? ""
                    self.mouseDownSelectionSnapshot = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
                    let context = self.selectionContext(
                        pid: frontApp.processIdentifier,
                        at: self.mouseDownPosition
                    )
                    self.mouseDownWasTextSelectionContext = context.isLikelyTextSelection
                    self.mouseDownContextRole = context.role
                    self.debugLog("mouseDown context=\(context.isLikelyTextSelection) role=\(context.role ?? "unknown")")
                } else {
                    self?.mouseDownWasTextSelectionContext = false
                    self?.mouseDownContextRole = nil
                }
                if let self {
                    self.debugLog("mouseDown at (\(Int(self.mouseDownPosition.x)), \(Int(self.mouseDownPosition.y)))")
                }
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
                self?.debugLog("mouseUp at (\(Int(mousePos.x)), \(Int(mousePos.y))), clickCount=\(clickCount)")
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
        mouseDownWasTextSelectionContext = false
        mouseDownContextRole = nil
        mouseDownSelectionSnapshot = ""
        lastMouseUpPoint = .zero
        lastMouseUpAt = 0
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

        let selectedText = Self.getSelectedTextViaAX(pid: pid)
        if selectedText == nil {
            axFailedApps.insert(pid)
            debugLog("AX unavailable for pid=\(pid), switch to pasteboard fallback")
            return
        }
        if let text = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Quick dedup: if same pid + same text as last poll, skip
            if pid == lastPollPid && text == lastPollResult { return }
            lastPollPid = pid
            lastPollResult = text
            // Polling keeps state only. Tooltip triggering is restricted to mouse-up path.
        } else {
            // Selection became empty (e.g. user cleared selection via keyboard/delete).
            // Clear immediately so tooltip/result panel are dismissed without waiting for mouse-up.
            lastPollPid = pid
            lastPollResult = ""
            guard !isMouseButtonDown else { return }
            clearSelection()
        }
    }

    /// Pure function — no mutable state access; safe to call from anywhere.
    nonisolated private static func getSelectedTextViaAX(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedElementRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusResult == .success, let focusedElement = focusedElementRef else {
            return nil
        }

        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = unsafeBitCast(focusedElement, to: AXUIElement.self)

        var selectedTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )

        if textResult == .success {
            return (selectedTextRef as? String) ?? ""
        }

        // AX attribute unavailable/failed: treat as AX unsupported for this app,
        // so caller can fall back to pasteboard strategy.
        return nil
    }

    // MARK: - Mouse-up based detection (Chrome, VS Code, etc.)

    private func checkSelectionAfterMouseUp(at mousePos: NSPoint, clickCount: Int) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        if frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        guard AppSettings.shared.isAppEnabled(bundleID: frontApp.bundleIdentifier) else {
            clearSelection()
            return
        }
        let pid = frontApp.processIdentifier
        let bundleID = frontApp.bundleIdentifier ?? ""

        let dx = mousePos.x - mouseDownPosition.x
        let dy = mousePos.y - mouseDownPosition.y
        let dragDistance = sqrt(dx * dx + dy * dy)
        let now = CFAbsoluteTimeGetCurrent()
        let dupDx = mousePos.x - lastMouseUpPoint.x
        let dupDy = mousePos.y - lastMouseUpPoint.y
        let dupDistance = sqrt(dupDx * dupDx + dupDy * dupDy)
        if now - lastMouseUpAt < 0.2, dupDistance < 2 {
            debugLog("mouseUp dedup ignored")
            return
        }
        lastMouseUpAt = now
        lastMouseUpPoint = mousePos
        // Single click with nearly no movement is usually just caret placement.
        let isLikelySelectionGesture = dragDistance > Self.selectionGestureThreshold || clickCount >= 2
        let mouseUpContext = selectionContext(pid: pid, at: mousePos)
        let isTextSelectionContext = mouseUpContext.isLikelyTextSelection
        let contextAllowsFallback = mouseDownWasTextSelectionContext && isTextSelectionContext
        let menuBarCoordinateMismatch = isLikelyExternalDisplayAXMenuBarMismatch(
            mouseDownRole: mouseDownContextRole,
            mouseUpRole: mouseUpContext.role
        )
        debugLog(
            "mouseUp eval pid=\(pid) drag=\(String(format: "%.2f", dragDistance)) clickCount=\(clickCount) " +
            "isLikelySelectionGesture=\(isLikelySelectionGesture) isTextSelectionContext=\(isTextSelectionContext) " +
            "role=\(mouseUpContext.role ?? "unknown") menuBarCoordinateMismatch=\(menuBarCoordinateMismatch)"
        )

        // First try AX API
        if let text = Self.getSelectedTextViaAX(pid: pid), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard isLikelySelectionGesture, contextAllowsFallback || menuBarCoordinateMismatch else {
                debugLog("mouseUp AX path blocked by gesture/context guard")
                clearSelection()
                return
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != mouseDownSelectionSnapshot else {
                debugLog("mouseUp AX path suppressed: same as mouseDown snapshot")
                return
            }
            debugLog("mouseUp AX path -> handleDetectedText textLen=\(text.count)")
            handleDetectedText(trimmed, at: mousePos)
            return
        }

        // Fallback: simulate Cmd+C and read pasteboard
        // Only for apps where AX failed, and only when gesture likely selected text.
        if axFailedApps.contains(pid) {
            // Finder's Cmd+C copies file names/paths, not text selection.
            // Disable pasteboard fallback there to avoid false positives while dragging windows.
            if bundleID == "com.apple.finder" {
                debugLog("mouseUp pasteboard fallback disabled for Finder")
                clearSelection()
                return
            }
            guard isLikelySelectionGesture, contextAllowsFallback || menuBarCoordinateMismatch else {
                debugLog("mouseUp pasteboard path blocked by gesture/context guard")
                clearSelection()
                return
            }
            getSelectedTextViaPasteboard { [weak self] text in
                guard let self else { return }
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed != self.mouseDownSelectionSnapshot else {
                        self.debugLog("mouseUp pasteboard path suppressed: same as mouseDown snapshot")
                        return
                    }
                    let now = CFAbsoluteTimeGetCurrent()
                    if trimmed == self.lastSelection, (now - self.lastSelectionAt) < 5.0 {
                        self.debugLog("mouseUp pasteboard path suppressed repeated same text within cooldown")
                        return
                    }
                    self.debugLog("mouseUp pasteboard path -> handleDetectedText textLen=\(text.count)")
                    self.handleDetectedText(trimmed, at: mousePos)
                } else {
                    // No text selected after mouse-up — selection was cleared
                    self.debugLog("mouseUp pasteboard path empty text -> clearSelection")
                    self.clearSelection()
                }
            }
            return
        }

        // AX returned empty/no selection — clear
        debugLog("mouseUp no selection -> clearSelection")
        clearSelection()
    }

    /// Best-effort guard to avoid copy-fallback false positives from non-text UI areas
    /// (e.g. title bar double-click, toolbar clicks).
    private func isLikelyTextSelectionContext(pid: pid_t, at point: NSPoint) -> Bool {
        selectionContext(pid: pid, at: point).isLikelyTextSelection
    }

    private func selectionContext(pid: pid_t, at point: NSPoint) -> SelectionContext {
        let appElement = AXUIElementCreateApplication(pid)

        var hitRef: AXUIElement?
        let hitStatus = AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &hitRef)
        guard hitStatus == .success, let hitElement = hitRef else {
            // If we cannot determine the role, keep old behavior to avoid regressions.
            return SelectionContext(isLikelyTextSelection: true, role: nil)
        }

        var roleRef: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(hitElement, kAXRoleAttribute as CFString, &roleRef)
        guard roleStatus == .success, let role = roleRef as? String else {
            return SelectionContext(isLikelyTextSelection: false, role: nil)
        }
        let allowedRoles: Set<String> = [
            kAXStaticTextRole as String,
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            "AXWebArea",
            "AXDocument",
            // Container roles that commonly host selectable text in many apps.
            "AXScrollArea",
            "AXGroup",
            "AXSplitGroup",
        ]
        let allowed = allowedRoles.contains(role)
        debugLog("hit role=\(role) allowed=\(allowed)")
        return SelectionContext(isLikelyTextSelection: allowed, role: role)
    }

    private func isLikelyExternalDisplayAXMenuBarMismatch(mouseDownRole: String?, mouseUpRole: String?) -> Bool {
        guard NSScreen.screens.count > 1 else { return false }
        return mouseDownRole == (kAXMenuBarRole as String) && mouseUpRole == (kAXMenuBarRole as String)
    }

    private struct SelectionContext {
        let isLikelyTextSelection: Bool
        let role: String?
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
                // Record the change count produced by OUR synthetic Cmd+C so we
                // can detect a *further* change before restoring.
                let ourChangeCount = pasteboard.changeCount

                // Restore the user's clipboard — but only if nothing has copied
                // over our synthetic copy in the meantime. If the user (or the
                // app) pressed Cmd+C themselves right after selecting, the
                // pasteboard advances past `ourChangeCount`; restoring here would
                // silently clobber their copy, forcing a second Cmd+C. Defer the
                // restore slightly and skip it when a newer copy is detected.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard pasteboard.changeCount == ourChangeCount else {
                        // A newer copy happened — leave it intact.
                        return
                    }
                    pasteboard.clearContents()
                    if let prev = previousContents {
                        pasteboard.setString(prev, forType: .string)
                    }
                }
            } else {
                newText = nil
            }
            completion(newText)
        }
    }

    // MARK: - Common handler (debounced)

    private func handleDetectedText(_ text: String, at position: NSPoint? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let origin = position ?? NSEvent.mouseLocation

        // Allow re-trigger for the same text if the mouse position moved significantly
        // (indicates a new selection gesture, e.g. re-selecting the same word).
        if trimmed == lastSelection {
            let dx = origin.x - lastSelectionOrigin.x
            let dy = origin.y - lastSelectionOrigin.y
            let distance = sqrt(dx * dx + dy * dy)
            guard distance > Self.positionThreshold else { return }
        }

        lastSelection = trimmed
        lastSelectionAt = CFAbsoluteTimeGetCurrent()
        lastSelectionOrigin = origin
        debugLog("handleDetectedText accepted len=\(trimmed.count) at (\(Int(origin.x)), \(Int(origin.y)))")

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
            lastSelectionAt = 0
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
