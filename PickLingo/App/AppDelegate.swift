import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBarController = MenuBarController()
    let accessibilityMonitor = AccessibilityMonitor()
    private var tooltipPanel: TooltipPanel?
    private var resultPanel: ResultPanelController?
    private var userInputPanel: UserInputPanelController?
    private var settingsWindow: NSWindow?
    private var appSwitchObserver: Any?

    // Cached state for plugin execution
    private var pendingSelectedText: String = ""
    private var pendingOrigin: NSPoint = .zero
    private var lastActiveAppPID: pid_t = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[PickLingo] App launched")
        menuBarController.setup()

        let granted = accessibilityMonitor.isAccessibilityGranted
        print("[PickLingo] Accessibility granted: \(granted)")
        if granted {
            startMonitoring()
        } else {
            showOnboarding()
        }
    }

    func startMonitoring() {
        let enabled = AppSettings.shared.isEnabled
        print("[PickLingo] startMonitoring, isEnabled: \(enabled)")
        guard enabled else { return }

        accessibilityMonitor.onTextSelected = { [weak self] text, origin in
            self?.showTooltip(for: text, at: origin)
        }
        accessibilityMonitor.onSelectionCleared = { [weak self] in
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

        userInputPanel?.onSubmit = { [weak self] userInput, thinkModeOverride in
            self?.executePlugin(plugin, userInput: userInput, thinkModeOverride: thinkModeOverride)
        }
        userInputPanel?.onCancel = { [weak self] in
            self?.userInputPanel?.dismiss()
        }

        userInputPanel?.show(plugin: plugin, selectedText: pendingSelectedText, at: pendingOrigin)
    }

    private func executePlugin(_ plugin: Plugin, userInput: String?, thinkModeOverride: Bool?) {
        if resultPanel == nil {
            resultPanel = ResultPanelController()
        }

        resultPanel?.show(
            for: pendingSelectedText,
            plugin: plugin,
            userInput: userInput,
            thinkModeOverride: thinkModeOverride,
            at: pendingOrigin
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
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "PickLingo Settings")
        window.minSize = NSSize(width: 520, height: 400)
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView {
            if self.accessibilityMonitor.isAccessibilityGranted {
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
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == settingsWindow {
            settingsWindow = nil
        }
    }
}
