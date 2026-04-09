import Cocoa
import SwiftUI

final class MenuBarController {
    private var statusItem: NSStatusItem!
    private let settings = AppSettings.shared

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "sparkles",
                accessibilityDescription: "PickLingo"
            )
        }

        statusItem.menu = buildMenu()
    }

    func rebuildMenu() {
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

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
