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
    var onOpenSettings: (() -> Void)?
    var onToggleEnabled: (() -> Void)?
    var onQuit: (() -> Void)?

    func show(
        plugin: Plugin,
        selectedText: String,
        at origin: NSPoint,
        placeholderOverride: String? = nil,
        showSelectionPreview: Bool = true,
        showQuickActions: Bool = false
    ) {
        dismiss()

        let inputView = UserInputView(
            plugin: plugin,
            selectedTextPreview: String(selectedText.prefix(100)),
            showSelectionPreview: showSelectionPreview,
            placeholderOverride: placeholderOverride,
            showQuickActions: showQuickActions,
            onSubmit: { [weak self] text, thinkModeOverride in
                self?.onSubmit?(text, thinkModeOverride)
                self?.dismiss()
            },
            onCancel: { [weak self] in
                self?.onCancel?()
                self?.dismiss()
            },
            onOpenSettings: { [weak self] in
                self?.onOpenSettings?()
                self?.dismiss()
            },
            onToggleEnabled: { [weak self] in
                self?.onToggleEnabled?()
            },
            onQuit: { [weak self] in
                self?.onQuit?()
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
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = hostingView
        panel.appearance = AppSettings.shared.appTheme.nsAppearance

        let panelSize = NSSize(width: max(fittingSize.width, 320), height: max(fittingSize.height, 120))
        let panelFrame = ScreenLocator.frame(for: panelSize, anchoredAt: origin)

        panel.setFrame(panelFrame, display: false)
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
    let showSelectionPreview: Bool
    let placeholderOverride: String?
    let showQuickActions: Bool
    let onSubmit: (String, Bool?) -> Void
    let onCancel: () -> Void
    let onOpenSettings: () -> Void
    let onToggleEnabled: () -> Void
    let onQuit: () -> Void

    @State private var inputText: String = ""
    @State private var requestThinkModeEnabled: Bool = AppSettings.shared.thinkModeEnabled
    @ObservedObject private var settings = AppSettings.shared
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
                if showQuickActions {
                    enabledToggle
                }
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

            if showSelectionPreview && !selectedTextPreview.isEmpty {
                // Selected text preview
                Text(selectedTextPreview + (selectedTextPreview.count >= 100 ? "…" : ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
            }

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

            if showQuickActions {
                quickActionsBar
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

    private var enabledToggle: some View {
        Toggle(
            "",
            isOn: Binding(
                get: { settings.isEnabled },
                set: { _ in onToggleEnabled() }
            )
        )
        .toggleStyle(.switch)
        .controlSize(.mini)
        .labelsHidden()
        .tint(.accentColor)
        .help(
            settings.isEnabled
                ? UIString("Disable PickLingo")
                : UIString("Enable PickLingo")
        )
    }

    private var quickActionsBar: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal, 14)

            HStack(spacing: 6) {
                quickActionButton(
                    icon: "gearshape",
                    label: UIString("Settings…"),
                    action: onOpenSettings
                )

                quickActionButton(
                    icon: "power",
                    label: UIString("Quit PickLingo"),
                    tint: .red,
                    action: onQuit
                )
            }
            .padding(.horizontal, 10)
        }
    }

    private func quickActionButton(
        icon: String,
        label: String,
        tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
        .help(label)
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
