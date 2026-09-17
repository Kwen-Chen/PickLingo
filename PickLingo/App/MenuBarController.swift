import Cocoa
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let settings = AppSettings.shared

    func setup() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "PickLingo"
            item.behavior = []
            statusItem = item
        }
        ensureVisible()
        rebuildMenu()
    }

    func ensureVisible() {
        guard let statusItem else { setup(); return }
        statusItem.isVisible = true
        if let button = statusItem.button {
            let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "PickLingo")
            symbol?.isTemplate = true
            symbol?.size = NSSize(width: 18, height: 18)
            button.image = symbol
            button.title = symbol == nil ? "PL" : ""
            button.toolTip = "PickLingo"
            button.setAccessibilityLabel("PickLingo")
        }
    }

    func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Refresh in place so this opening uses current clipboard, app, and language.
        let updated = buildMenu()
        menu.removeAllItems()
        for item in updated.items {
            updated.removeItem(item)
            menu.addItem(item)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let clipboardItem = NSMenuItem(
            title: UIString("Process Copied Text"),
            action: #selector(AppDelegate.processCopiedText), keyEquivalent: ""
        )
        clipboardItem.isEnabled = !(NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        menu.addItem(clipboardItem)
        menu.addItem(.separator())

        // Enable/Disable toggle
        let toggleItem = NSMenuItem(
            title: settings.isEnabled
                ? UIString("Disable PickLingo")
                : UIString("Enable PickLingo"),
            action: #selector(AppDelegate.toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.state = settings.isEnabled ? .on : .off
        menu.addItem(toggleItem)
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           let bundleID = app.bundleIdentifier {
            let item = NSMenuItem(
                title: UIString("Disable in Current App") + " (" + (app.localizedName ?? bundleID) + ")",
                action: #selector(AppDelegate.toggleCurrentAppScope), keyEquivalent: ""
            )
            item.state = settings.isAppBlacklisted(bundleID: bundleID) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Settings
        menu.addItem(
            withTitle: UIString("Settings…"),
            action: #selector(AppDelegate.openSettings),
            keyEquivalent: ","
        )

        menu.addItem(.separator())

        // Quit
        menu.addItem(
            withTitle: UIString("Quit PickLingo"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        return menu
    }
}
