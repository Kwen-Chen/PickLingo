import Cocoa
import SwiftUI
import Combine
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBarController = MenuBarController()
    let accessibilityMonitor = AccessibilityMonitor()
    private var tooltipPanel: TooltipPanel?
    private var resultPanel: ResultPanelController?
    private var userInputPanel: UserInputPanelController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var appSwitchObserver: Any?
    private var themeCancellable: AnyCancellable?
    private var quickAskFlagsMonitor: Any?
    private var quickAskKeyDownMonitor: Any?
    private var commandTapInProgress = false
    private var commandTapHadOtherModifiers = false
    private var commandTapHadNonModifierKey = false
    private var lastCommandTapTimestamp: TimeInterval = 0
    private var commandTapCount = 0

    // Cached state for plugin execution
    private var pendingSelectedText: String = ""
    private var pendingOrigin: NSPoint = .zero
    private var lastActiveAppPID: pid_t = 0
    private var lastTooltipSelectionText: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[PickLingo] App launched")
        menuBarController.setup()
        bindThemeUpdates()
        setupQuickAskMonitoring()

        let granted = accessibilityMonitor.isAccessibilityGranted
        print("[PickLingo] Accessibility granted: \(granted)")
        if granted {
            scheduleStartMonitoring()
        } else {
            showOnboarding()
        }
    }

    private func scheduleStartMonitoring(delay: TimeInterval = 0.4) {
        Task { @MainActor in
            // TCC permission flips can be slightly delayed after user grants access.
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard self.accessibilityMonitor.isAccessibilityGranted else { return }
            self.startMonitoring()
        }
    }

    func startMonitoring() {
        let enabled = AppSettings.shared.isEnabled
        print("[PickLingo] startMonitoring, isEnabled: \(enabled)")
        guard enabled else { return }

        if let obs = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appSwitchObserver = nil
        }

        accessibilityMonitor.onTextSelected = { [weak self] text, origin in
            self?.showTooltip(for: text, at: origin)
        }
        accessibilityMonitor.onSelectionCleared = { [weak self] in
            self?.lastTooltipSelectionText = nil
            let ownPID = ProcessInfo.processInfo.processIdentifier
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID {
                return
            }
            self?.hideAll()
        }
        accessibilityMonitor.startMonitoring()

        // Track current app PID
        lastActiveAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0

        // Dismiss everything when user switches to a DIFFERENT app
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                let newPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier ?? 0
                let ownPID = ProcessInfo.processInfo.processIdentifier

                // Ignore when our own app activates (e.g. clicking the result panel)
                // — keep lastActiveAppPID unchanged so returning to the original
                // app is not treated as an app switch.
                guard newPID != ownPID else { return }

                if newPID != self.lastActiveAppPID {
                    self.hideAll()
                    self.accessibilityMonitor.clearSelection()
                }
                self.lastActiveAppPID = newPID
            }
        }
    }

    func stopMonitoring() {
        accessibilityMonitor.stopMonitoring()
        if let obs = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appSwitchObserver = nil
        }
        hideAll()
    }

    private func setupQuickAskMonitoring() {
        if let monitor = quickAskFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            quickAskFlagsMonitor = nil
        }
        if let monitor = quickAskKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            quickAskKeyDownMonitor = nil
        }

        quickAskFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleQuickAskFlagsChanged(event)
            }
        }
        quickAskKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleQuickAskKeyDown(event)
            }
        }
    }

    // MARK: - Tooltip

    private func showTooltip(for text: String, at origin: NSPoint) {
        #if DEBUG
        let app = NSWorkspace.shared.frontmostApplication
        let bid = app?.bundleIdentifier ?? "unknown"
        let pid = app?.processIdentifier ?? 0
        print("[PickLingo][DBG][Tooltip] showTooltip textLen=\(text.count) at (\(Int(origin.x)), \(Int(origin.y))) app=\(bid) pid=\(pid)")
        #endif

        // If the result panel is currently visible, don't interrupt it
        // with a new tooltip. The user is reading/interacting with results.
        if let rp = resultPanel, rp.isVisible {
            return
        }

        // Only show once for the same active selection text. It resets when
        // AccessibilityMonitor reports selection cleared.
        if lastTooltipSelectionText == text {
            return
        }
        lastTooltipSelectionText = text

        // Save state for later plugin execution
        pendingSelectedText = text
        pendingOrigin = origin

        userInputPanel?.dismiss()

        if tooltipPanel == nil {
            tooltipPanel = TooltipPanel()
        }
        tooltipPanel?.applyCurrentTheme()

        tooltipPanel?.onPluginSelected = { [weak self] plugin in
            self?.handlePluginSelected(plugin)
        }

        tooltipPanel?.show(at: origin)
    }

    private func hideTooltip() {
        tooltipPanel?.fadeOut()
    }

    private func hideAll() {
        hideTooltip()
        resultPanel?.dismissIfNotPinned()
        userInputPanel?.dismiss()
    }

    // MARK: - Quick Ask

    private func handleQuickAskFlagsChanged(_ event: NSEvent) {
        guard AppSettings.shared.quickAskEnabled else {
            resetCommandTapState()
            return
        }

        guard resolvedQuickAskTrigger() == .doubleCommandTap else { return }
        guard event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand) else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandPressed = flags.contains(.command)

        if isCommandPressed {
            commandTapInProgress = true
            commandTapHadOtherModifiers = flags.contains(.shift) || flags.contains(.option) || flags.contains(.control)
            commandTapHadNonModifierKey = false
            return
        }

        guard commandTapInProgress else { return }
        commandTapInProgress = false

        guard !commandTapHadOtherModifiers, !commandTapHadNonModifierKey else {
            resetCommandTapState()
            return
        }

        let now = Date().timeIntervalSinceReferenceDate
        if now - lastCommandTapTimestamp <= 0.35 {
            commandTapCount += 1
        } else {
            commandTapCount = 1
        }
        lastCommandTapTimestamp = now

        if commandTapCount >= 2 {
            resetCommandTapState()
            showQuickAskWindow()
        }
    }

    private func handleQuickAskKeyDown(_ event: NSEvent) {
        guard AppSettings.shared.quickAskEnabled else {
            resetCommandTapState()
            return
        }

        if commandTapInProgress {
            commandTapHadNonModifierKey = true
        }

        guard !event.isARepeat else { return }
        guard case .keyCombo(let key, let modifiers) = resolvedQuickAskTrigger() else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .shift, .option, .control])
        guard flags == modifiers else { return }

        let pressedKey = normalizedEventKey(event)
        guard pressedKey == key else { return }
        showQuickAskWindow()
    }

    private func resetCommandTapState() {
        commandTapInProgress = false
        commandTapHadOtherModifiers = false
        commandTapHadNonModifierKey = false
        commandTapCount = 0
        lastCommandTapTimestamp = 0
    }

    private func resolvedQuickAskTrigger() -> QuickAskShortcutTrigger {
        QuickAskShortcutParser.parse(AppSettings.shared.quickAskShortcut) ?? .doubleCommandTap
    }

    private func normalizedEventKey(_ event: NSEvent) -> String? {
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            return "return"
        }
        if event.keyCode == UInt16(kVK_Tab) {
            return "tab"
        }
        if event.keyCode == UInt16(kVK_Escape) {
            return "escape"
        }
        if event.keyCode == UInt16(kVK_Space) {
            return "space"
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 else {
            return nil
        }
        return chars
    }

    private func showQuickAskWindow() {
        guard AppSettings.shared.quickAskEnabled else { return }
        guard let askPlugin = resolvedAskPluginForQuickAsk() else { return }

        tooltipPanel?.fadeOut()

        if userInputPanel == nil {
            userInputPanel = UserInputPanelController()
        }
        userInputPanel?.applyCurrentTheme()

        let origin = NSPoint(
            x: NSScreen.main?.visibleFrame.midX ?? NSEvent.mouseLocation.x,
            y: NSScreen.main?.visibleFrame.midY ?? NSEvent.mouseLocation.y
        )
        pendingSelectedText = ""
        pendingOrigin = origin

        userInputPanel?.onSubmit = { [weak self] userInput, thinkModeOverride in
            self?.executePlugin(
                askPlugin,
                selectedText: "",
                userInput: userInput,
                thinkModeOverride: thinkModeOverride,
                origin: origin
            )
        }
        userInputPanel?.onCancel = { [weak self] in
            self?.userInputPanel?.dismiss()
        }
        userInputPanel?.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        userInputPanel?.onToggleEnabled = { [weak self] in
            self?.toggleEnabled()
        }
        userInputPanel?.onQuit = {
            NSApp.terminate(nil)
        }

        userInputPanel?.show(
            plugin: askPlugin,
            selectedText: "",
            at: origin,
            placeholderOverride: UIString("Type your question..."),
            showSelectionPreview: false,
            showQuickActions: true
        )
    }

    private func resolvedAskPluginForQuickAsk() -> Plugin? {
        if let ask = PluginManager.shared.plugins.first(where: { $0.builtInID == "ask" }) {
            return ask
        }
        return Plugin.defaultBuiltIn(id: "ask")
    }

    // MARK: - Plugin Execution

    private func handlePluginSelected(_ plugin: Plugin) {
        tooltipPanel?.cancelAutoHide()
        tooltipPanel?.orderOut(nil)

        if plugin.needsUserInput {
            showUserInputPanel(for: plugin)
        } else {
            executePlugin(plugin, userInput: nil, thinkModeOverride: nil)
        }
    }

    private func showUserInputPanel(for plugin: Plugin) {
        if userInputPanel == nil {
            userInputPanel = UserInputPanelController()
        }
        userInputPanel?.applyCurrentTheme()

        userInputPanel?.onSubmit = { [weak self] userInput, thinkModeOverride in
            self?.executePlugin(plugin, userInput: userInput, thinkModeOverride: thinkModeOverride)
        }
        userInputPanel?.onCancel = { [weak self] in
            self?.userInputPanel?.dismiss()
        }

        userInputPanel?.show(plugin: plugin, selectedText: pendingSelectedText, at: pendingOrigin)
    }

    private func executePlugin(_ plugin: Plugin, userInput: String?, thinkModeOverride: Bool?) {
        executePlugin(
            plugin,
            selectedText: pendingSelectedText,
            userInput: userInput,
            thinkModeOverride: thinkModeOverride,
            origin: pendingOrigin
        )
    }

    private func executePlugin(
        _ plugin: Plugin,
        selectedText: String,
        userInput: String?,
        thinkModeOverride: Bool?,
        origin: NSPoint
    ) {
        if plugin.isLocalActionPlugin && !plugin.showResultPanel {
            executeLocalActionWithoutResultPanel(plugin, selectedText: selectedText, userInput: userInput, origin: origin)
            return
        }

        if resultPanel == nil {
            resultPanel = ResultPanelController()
        }
        resultPanel?.applyCurrentTheme()

        pendingSelectedText = selectedText
        pendingOrigin = origin
        let sourceAppPID = lastActiveAppPID != 0
            ? lastActiveAppPID
            : (NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)

        resultPanel?.show(
            for: selectedText,
            plugin: plugin,
            userInput: userInput,
            thinkModeOverride: thinkModeOverride,
            sourceAppPID: sourceAppPID,
            at: origin
        )
    }

    private func executeLocalActionWithoutResultPanel(
        _ plugin: Plugin,
        selectedText: String,
        userInput: String?,
        origin: NSPoint
    ) {
        pendingSelectedText = selectedText
        pendingOrigin = origin

        Task.detached {
            do {
                _ = try LocalActionExecutor.shared.execute(
                    plugin: plugin,
                    selectedText: selectedText,
                    userInput: userInput,
                    source: nil,
                    target: nil
                )
            } catch {
                await MainActor.run {
                    self.showLocalActionFailure(error)
                }
            }
        }
    }

    private func showLocalActionFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = UIString("Local Action Failed")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: UIString("OK"))
        alert.runModal()
    }

    // MARK: - Actions

    @objc func toggleEnabled() {
        let settings = AppSettings.shared
        settings.isEnabled.toggle()
        if settings.isEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
        menuBarController.rebuildMenu()
    }

    @objc func openSettings() {
        // For LSUIElement (accessory) apps, showing a window before the app
        // is fully active races SwiftUI's first layout pass and can leave
        // Toggle(.switch) thumbs measured at zero width. NSApp.activate()
        // is asynchronous, so we activate first, then defer the actual
        // window display to the next runloop tick once the app is stable.
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            window.appearance = AppSettings.shared.appTheme.nsAppearance
            DispatchQueue.main.async {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(nil)
            }
            return
        }

        let settingsView = SettingsView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.title = UIString("PickLingo Settings")
        window.minSize = NSSize(width: 640, height: 420)
        window.appearance = AppSettings.shared.appTheme.nsAppearance
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window

        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
        }
    }

    private func showOnboarding() {
        if let window = onboardingWindow {
            window.appearance = AppSettings.shared.appTheme.nsAppearance
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView {
            if self.accessibilityMonitor.isAccessibilityGranted {
                self.onboardingWindow?.close()
                self.scheduleStartMonitoring()
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to PickLingo")
        window.appearance = AppSettings.shared.appTheme.nsAppearance
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func bindThemeUpdates() {
        themeCancellable = AppSettings.shared.$appTheme
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyThemeToOpenWindows()
            }
    }

    private func applyThemeToOpenWindows() {
        let appearance = AppSettings.shared.appTheme.nsAppearance
        settingsWindow?.appearance = appearance
        onboardingWindow?.appearance = appearance
        tooltipPanel?.applyCurrentTheme()
        userInputPanel?.applyCurrentTheme()
        resultPanel?.applyCurrentTheme()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == settingsWindow {
            settingsWindow = nil
        }
        if (notification.object as? NSWindow) == onboardingWindow {
            onboardingWindow = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = quickAskFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            quickAskFlagsMonitor = nil
        }
        if let monitor = quickAskKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            quickAskKeyDownMonitor = nil
        }
    }
}
