import Cocoa
import SwiftUI

// MARK: - Keyable Panel (allows text field to receive focus)

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Panel Controller

@MainActor
final class UserInputPanelController {
    private var panel: NSPanel?
    var onSubmit: ((String, Bool?) -> Void)?
    var onCancel: (() -> Void)?

    func show(plugin: Plugin, selectedText: String, at origin: NSPoint, placeholderOverride: String? = nil) {
        dismiss()

        let inputView = UserInputView(
            plugin: plugin,
            selectedTextPreview: String(selectedText.prefix(100)),
            placeholderOverride: placeholderOverride,
            onSubmit: { [weak self] text, thinkModeOverride in
                self?.onSubmit?(text, thinkModeOverride)
                self?.dismiss()
            },
            onCancel: { [weak self] in
                self?.onCancel?()
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: inputView)
        let fittingSize = hostingView.fittingSize

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: max(fittingSize.width, 320), height: max(fittingSize.height, 120)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = hostingView
        panel.appearance = AppSettings.shared.appTheme.nsAppearance

        // Position below cursor
        let panelSize = NSSize(width: max(fittingSize.width, 320), height: max(fittingSize.height, 120))
        var panelOrigin = NSPoint(x: origin.x - panelSize.width / 2, y: origin.y - panelSize.height - 10)

        // Clamp to screen
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let sf = screen.visibleFrame
            if panelOrigin.x + panelSize.width > sf.maxX { panelOrigin.x = sf.maxX - panelSize.width - 8 }
            if panelOrigin.x < sf.minX { panelOrigin.x = sf.minX + 8 }
            if panelOrigin.y < sf.minY { panelOrigin.y = origin.y + 10 }
            if panelOrigin.y + panelSize.height > sf.maxY { panelOrigin.y = sf.maxY - panelSize.height - 8 }
        }

        panel.setFrameOrigin(panelOrigin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Need to become key so the text field can receive input
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }

        self.panel = panel
    }

    func applyCurrentTheme() {
        panel?.appearance = AppSettings.shared.appTheme.nsAppearance
    }

    func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        self.panel = nil
    }
}

// MARK: - SwiftUI View

struct UserInputView: View {
    let plugin: Plugin
    let selectedTextPreview: String
    let placeholderOverride: String?
    let onSubmit: (String, Bool?) -> Void
    let onCancel: () -> Void

    @State private var inputText: String = ""
    @State private var requestThinkModeEnabled: Bool = AppSettings.shared.thinkModeEnabled
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: plugin.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(plugin.uiDisplayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Selected text preview
            Text(selectedTextPreview + (selectedTextPreview.count >= 100 ? "…" : ""))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .padding(.horizontal, 14)

            // Input field
            HStack(spacing: 8) {
                TextField(placeholderText, text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit {
                        submitIfValid()
                    }

                Button(action: submitIfValid) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor.opacity(isFocused ? 0.5 : 0.0), lineWidth: 1.5)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
            .padding(.horizontal, 14)

            Toggle(String(localized: "Enable Think Mode for this request"), isOn: $requestThinkModeEnabled)
                .font(.system(size: 12))
                .disabled(!AppSettings.shared.streamingEnabled)
                .padding(.horizontal, 14)

            if !AppSettings.shared.streamingEnabled {
                Text(String(localized: "Think Mode requires streaming to be enabled."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 12)
        .frame(width: 320)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 3, x: 0, y: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            isFocused = true
        }
    }

    private func submitIfValid() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let globalThinkMode = AppSettings.shared.thinkModeEnabled
        let thinkModeOverride: Bool? = requestThinkModeEnabled == globalThinkMode ? nil : requestThinkModeEnabled
        onSubmit(trimmed, thinkModeOverride)
    }

    private var placeholderText: String {
        if let placeholderOverride, !placeholderOverride.isEmpty {
            return placeholderOverride
        }
        if let customPlaceholder = plugin.userInputPlaceholder, !customPlaceholder.isEmpty {
            return customPlaceholder
        }
        return UIString("Type your question...")
    }
}
