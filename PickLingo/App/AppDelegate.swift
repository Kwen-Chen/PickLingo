import Cocoa
import SwiftUI
import Combine

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

    // Cached state for plugin execution
    private var pendingSelectedText: String = ""
    private var pendingOrigin: NSPoint = .zero
    private var lastActiveAppPID: pid_t = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[PickLingo] App launched")
        menuBarController.setup()
        bindThemeUpdates()

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

    // MARK: - Tooltip

    private func showTooltip(for text: String, at origin: NSPoint) {
        // If the result panel is currently visible, don't interrupt it
        // with a new tooltip. The user is reading/interacting with results.
        if let rp = resultPanel, rp.isVisible {
            return
        }

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
        if resultPanel == nil {
            resultPanel = ResultPanelController()
        }
        resultPanel?.applyCurrentTheme()

        pendingSelectedText = selectedText
        pendingOrigin = origin

        resultPanel?.show(
            for: selectedText,
            plugin: plugin,
            userInput: userInput,
            thinkModeOverride: thinkModeOverride,
            at: origin
        )
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
        if let window = settingsWindow {
            window.appearance = AppSettings.shared.appTheme.nsAppearance
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = UIString("PickLingo Settings")
        window.minSize = NSSize(width: 640, height: 420)
        window.appearance = AppSettings.shared.appTheme.nsAppearance
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
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
}
