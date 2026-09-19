import Cocoa
import SwiftUI
import Combine
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBarController = MenuBarController()
    let accessibilityMonitor = AccessibilityMonitor.shared
    private var tooltipPanel: TooltipPanel?
    private var resultPanel: ResultPanelController?
    private var userInputPanel: UserInputPanelController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var appSwitchObserver: Any?
    private var themeCancellable: AnyCancellable?
    private var settingsCancellables = Set<AnyCancellable>()
    private var quickAskLocalFlagsMonitor: Any?
    private var quickAskLocalKeyDownMonitor: Any?
    private var commandTapInProgress = false
    private var commandTapHadOtherModifiers = false
    private var commandTapHadNonModifierKey = false
    private var lastCommandTapTimestamp: TimeInterval = 0
    private var commandTapCount = 0
    private var commandPressedAt: TimeInterval = 0

    // Cached state for plugin execution
    private var pendingSelectedText: String = ""
    private var pendingOrigin: NSPoint = .zero
    private var lastActiveAppPID: pid_t = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[PickLingo] App launched")
        setupApplicationMenu()
        menuBarController.setup()
        bindThemeUpdates()
        bindBehaviorUpdates()
        startMonitoring()

        let granted = accessibilityMonitor.isAccessibilityGranted
        print("[PickLingo] Accessibility granted: \(granted)")
        if !granted {
            showOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController.ensureVisible()
        openSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        menuBarController.ensureVisible()
        accessibilityMonitor.refreshMonitoring(restart: true)
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
            let ownPID = ProcessInfo.processInfo.processIdentifier
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID {
                self?.hideTooltip()
                return
            }
            self?.hideAll()
        }
        accessibilityMonitor.startMonitoring()
        setupQuickAskMonitoring()

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
                self.accessibilityMonitor.prepareActiveApplication()
            }
        }
    }

    func stopMonitoring() {
        removeQuickAskMonitors()
        resetCommandTapState()
        accessibilityMonitor.stopMonitoring()
        if let obs = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appSwitchObserver = nil
        }
        hideAll()
    }

    private func removeQuickAskMonitors() {
        accessibilityMonitor.onGlobalKeyEvent = nil
        if let monitor = quickAskLocalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            quickAskLocalFlagsMonitor = nil
        }
        if let monitor = quickAskLocalKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            quickAskLocalKeyDownMonitor = nil
        }
    }

    private func setupQuickAskMonitoring() {
        removeQuickAskMonitors()
        resetCommandTapState()
        guard AppSettings.shared.isEnabled, AppSettings.shared.quickAskEnabled,
              accessibilityMonitor.monitoringState == .active else { return }

        accessibilityMonitor.onGlobalKeyEvent = { [weak self] event in
            if event.type == .flagsChanged {
                self?.handleQuickAskFlagsChanged(event)
            } else {
                self?.handleQuickAskKeyDown(event)
            }
        }

        quickAskLocalFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleQuickAskFlagsChanged(event)
            return event
        }
        quickAskLocalKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleQuickAskKeyDown(event)
            return event
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

        guard !PluginManager.shared.enabledPlugins().isEmpty else { return }

        // Save state for later plugin execution
        pendingSelectedText = text
        pendingOrigin = origin
        if NSApp.keyWindow?.identifier == AccessibilityMonitor.settingsWindowIdentifier,
           NSApp.isActive {
            // Never send Insert/Replace to the previously used external app
            // when the selection actually came from our settings window.
            lastActiveAppPID = ProcessInfo.processInfo.processIdentifier
        }

        userInputPanel?.dismiss()

        if tooltipPanel == nil {
            tooltipPanel = TooltipPanel()
        }
        tooltipPanel?.applyCurrentTheme()

        tooltipPanel?.onPluginSelected = { [weak self] plugin in
            self?.handlePluginSelected(plugin)
        }

        tooltipPanel?.show(at: origin, selectionBounds: accessibilityMonitor.selectionBounds)
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
        guard AppSettings.shared.isEnabled, AppSettings.shared.quickAskEnabled else {
            resetCommandTapState()
            return
        }

        guard resolvedQuickAskTrigger() == .doubleCommandTap else { return }
        guard event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand) else {
            if commandTapInProgress { commandTapHadOtherModifiers = true }
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandPressed = flags.contains(.command)

        if isCommandPressed {
            commandTapInProgress = true
            commandPressedAt = event.timestamp
            commandTapHadOtherModifiers = flags.contains(.shift) || flags.contains(.option) || flags.contains(.control)
            commandTapHadNonModifierKey = false
            return
        }

        guard commandTapInProgress else { return }
        commandTapInProgress = false

        guard !commandTapHadOtherModifiers, !commandTapHadNonModifierKey,
              event.timestamp - commandPressedAt <= 0.3 else {
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
        guard AppSettings.shared.isEnabled, AppSettings.shared.quickAskEnabled else {
            resetCommandTapState()
            return
        }

        // Any intervening key breaks a double-tap sequence, including Cmd+C/Cmd+V.
        if commandTapInProgress { commandTapHadNonModifierKey = true }
        commandTapCount = 0
        lastCommandTapTimestamp = 0

        guard !event.isARepeat else { return }
        guard case .keyCombo(let key, let modifiers)? = resolvedQuickAskTrigger() else { return }

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

    private func resolvedQuickAskTrigger() -> QuickAskShortcutTrigger? {
        QuickAskShortcutParser.parse(AppSettings.shared.quickAskShortcut)
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
        guard AppSettings.shared.isEnabled, AppSettings.shared.quickAskEnabled else { return }
        guard let askPlugin = resolvedAskPluginForQuickAsk() else { return }

        tooltipPanel?.fadeOut()

        if userInputPanel == nil {
            userInputPanel = UserInputPanelController()
        }
        userInputPanel?.applyCurrentTheme()

        let mouseLocation = NSEvent.mouseLocation
        let visibleFrame = ScreenLocator.visibleFrame(for: mouseLocation)
        let origin = NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)
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
        let basePlugin = PluginManager.shared.plugins.first(where: { $0.builtInID == "ask" })
            ?? Plugin.defaultBuiltIn(id: "ask")
        guard var askPlugin = basePlugin else { return nil }

        let customPrompt = AppSettings.shared.quickAskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        askPlugin.prompt = customPrompt.isEmpty ? AppSettings.defaultQuickAskPrompt : customPrompt
        return askPlugin
    }

    // MARK: - Plugin Execution

    private func handlePluginSelected(_ plugin: Plugin) {
        tooltipPanel?.dismiss()

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
                _ = try await LocalActionExecutor.shared.execute(
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
    }

    @objc func processCopiedText() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        // Explicit user action; read only. Menu opening does not replace the source app.
        let app = NSWorkspace.shared.frontmostApplication
        if let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastActiveAppPID = app.processIdentifier
        }
        resultPanel?.dismiss()
        accessibilityMonitor.clearSelection()
        showTooltip(for: text, at: NSEvent.mouseLocation)
    }

    @objc func toggleCurrentAppScope() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier else { return }
        let settings = AppSettings.shared
        settings.setAppBlacklisted(!settings.isAppBlacklisted(bundleID: bundleID), for: bundleID)
    }

    private func bindBehaviorUpdates() {
        AppSettings.shared.$interfaceLanguage.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.setupApplicationMenu()
                self?.settingsWindow?.title = UIString("PickLingo Settings")
            }.store(in: &settingsCancellables)
        accessibilityMonitor.$monitoringState.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.setupQuickAskMonitoring() }
            .store(in: &settingsCancellables)
        AppSettings.shared.$isEnabled.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.startMonitoring() } else { self.stopMonitoring() }
                self.resetCommandTapState()
                self.menuBarController.rebuildMenu()
            }.store(in: &settingsCancellables)
        AppSettings.shared.$quickAskEnabled.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.setupQuickAskMonitoring() }
            .store(in: &settingsCancellables)
        AppSettings.shared.$appEnabledOverrides.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.accessibilityMonitor.clearSelection()
                self?.hideAll()
                self?.menuBarController.rebuildMenu()
            }.store(in: &settingsCancellables)
    }

    @objc func openSettings() {
        // For LSUIElement (accessory) apps, showing a window before the app
        // is fully active races SwiftUI's first layout pass and can leave
        // Toggle(.switch) thumbs measured at zero width. NSApp.activate()
        // is asynchronous, so we activate first, then defer the actual
        // window display to the next runloop tick once the app is stable.
        NSApp.setActivationPolicy(.regular)
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
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.title = UIString("PickLingo Settings")
        window.identifier = AccessibilityMonitor.settingsWindowIdentifier
        window.contentMinSize = NSSize(width: 860, height: 560)
        window.appearance = AppSettings.shared.appTheme.nsAppearance
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
        }
    }

    private func setupApplicationMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(title: "PickLingo")
        appMenu.addItem(withTitle: UIString("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: UIString("Quit PickLingo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Native responder-chain actions preserve selection and work in both
        // SwiftUI selectable text and AppKit field editors without copying twice.
        let editMenu = NSMenu(title: UIString("Edit"))
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
                                     ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: UIString(title), action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: UIString("Edit"), action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        main.addItem(editItem)
        let windowMenu = NSMenu(title: UIString("Window"))
        windowMenu.addItem(withTitle: UIString("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: UIString("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem(title: UIString("Window"), action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
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
                self.startMonitoring()
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
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

private final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        AccessibilityMonitor.shared.finishSettingsMouseTracking(event, in: self)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == settingsWindow {
            settingsWindow = nil
            accessibilityMonitor.clearSelection()
            NSApp.setActivationPolicy(.accessory)
        }
        if (notification.object as? NSWindow) == onboardingWindow {
            onboardingWindow = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopMonitoring()
        AppSettings.shared.saveImmediately()
        PluginManager.shared.saveImmediately()
    }
}
