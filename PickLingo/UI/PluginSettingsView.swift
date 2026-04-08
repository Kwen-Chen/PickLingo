import SwiftUI

struct PluginSettingsView: View {
    @ObservedObject private var pluginManager = PluginManager.shared
    @State private var selectedPluginID: UUID?
    @State private var showingDeleteConfirmation = false
    @State private var pluginToDelete: Plugin?

    var body: some View {
        HSplitView {
            // Left: Plugin list
            pluginListView
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

            // Right: Edit panel
            pluginEditView
                .frame(minWidth: 280, idealWidth: 320)
        }
        .frame(minHeight: 360)
    }

    // MARK: - Plugin List

    private var pluginListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Plugins"))
                    .font(.headline)
                Spacer()
                Button(action: addNewPlugin) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Add new plugin"))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            List(selection: $selectedPluginID) {
                ForEach(pluginManager.plugins) { plugin in
                    PluginListRow(plugin: plugin, onToggle: { enabled in
                        var updated = plugin
                        updated.isEnabled = enabled
                        pluginManager.updatePlugin(updated)
                    })
                    .tag(plugin.id)
                }
                .onMove { from, to in
                    pluginManager.movePlugin(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.sidebar)

            // Bottom bar
            HStack {
                Button(String(localized: "Reset All")) {
                    pluginManager.resetToDefaults()
                    selectedPluginID = nil
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Plugin Edit Panel

    @ViewBuilder
    private var pluginEditView: some View {
        if let id = selectedPluginID,
           let index = pluginManager.plugins.firstIndex(where: { $0.id == id }) {
            PluginEditView(
                plugin: $pluginManager.plugins[index],
                onSave: {
                    pluginManager.save()
                },
                onDelete: {
                    pluginToDelete = pluginManager.plugins[index]
                    showingDeleteConfirmation = true
                },
                onReset: {
                    pluginManager.resetBuiltInPlugin(pluginManager.plugins[index])
                }
            )
            .id(id) // Force re-render when selection changes
            .alert(String(localized: "Delete Plugin?"), isPresented: $showingDeleteConfirmation) {
                Button(String(localized: "Delete"), role: .destructive) {
                    if let p = pluginToDelete {
                        selectedPluginID = nil
                        pluginManager.deletePlugin(p)
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "This plugin will be permanently removed."))
            }
        } else {
            VStack {
                Spacer()
                Text(String(localized: "Select a plugin to edit"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func addNewPlugin() {
        let newPlugin = Plugin(
            id: UUID(),
            name: String(localized: "New Plugin"),
            icon: "star",
            prompt: "You are a helpful assistant. Process the following text:\n\n{selected_text}",
            isEnabled: true,
            order: (pluginManager.plugins.map(\.order).max() ?? -1) + 1,
            isBuiltIn: false,
            needsUserInput: false,
            userInputPlaceholder: nil,
            builtInID: nil,
            enabledActions: .all,
            showLanguageControls: false
        )
        pluginManager.addPlugin(newPlugin)
        selectedPluginID = newPlugin.id
    }
}

// MARK: - Plugin List Row

struct PluginListRow: View {
    let plugin: Plugin
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Image(systemName: plugin.icon)
                .font(.system(size: 12))
                .foregroundStyle(plugin.isEnabled ? .primary : .tertiary)
                .frame(width: 18)

            Text(plugin.name)
                .font(.system(size: 13))
                .foregroundStyle(plugin.isEnabled ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Plugin Edit View

struct PluginEditView: View {
    @Binding var plugin: Plugin
    let onSave: () -> Void
    let onDelete: () -> Void
    let onReset: () -> Void

    // Common SF Symbol names for the picker
    private let commonIcons = [
        "translate", "book", "wand.and.stars", "text.quote",
        "bubble.left.and.text.bubble.right", "star", "lightbulb",
        "pencil", "doc.text", "magnifyingglass", "brain.head.profile",
        "text.badge.checkmark", "character.book.closed", "list.bullet",
        "arrow.triangle.2.circlepath", "sparkles", "text.alignleft",
        "globe", "abc", "textformat", "highlighter", "bookmark",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Name"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Plugin name"), text: $plugin.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: plugin.name) { _, _ in onSave() }
                }

                // Icon
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Icon"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        // Preview
                        Image(systemName: plugin.icon)
                            .font(.system(size: 18))
                            .frame(width: 32, height: 32)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            }

                        // Picker
                        Picker("", selection: $plugin.icon) {
                            ForEach(commonIcons, id: \.self) { icon in
                                Label(icon, systemImage: icon)
                                    .tag(icon)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                        .onChange(of: plugin.icon) { _, _ in onSave() }

                        Spacer()
                    }
                }

                // Prompt
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "System Prompt"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $plugin.prompt)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                }
                        }
                        .frame(minHeight: 120)
                        .onChange(of: plugin.prompt) { _, _ in onSave() }

                    // Placeholder hints
                    HStack(spacing: 6) {
                        Text(String(localized: "Placeholders:"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        PlaceholderChip("{selected_text}")
                        PlaceholderChip("{user_input}")
                        PlaceholderChip("{source}")
                        PlaceholderChip("{target}")
                    }
                }

                // User Input toggle
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(String(localized: "Requires user input"), isOn: $plugin.needsUserInput)
                        .onChange(of: plugin.needsUserInput) { _, _ in onSave() }

                    if plugin.needsUserInput {
                        TextField(
                            String(localized: "Input placeholder"),
                            text: Binding(
                                get: { plugin.userInputPlaceholder ?? "" },
                                set: { plugin.userInputPlaceholder = $0.isEmpty ? nil : $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onChange(of: plugin.userInputPlaceholder) { _, _ in onSave() }
                    }
                }

                // Language controls toggle
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(String(localized: "Show source/target language controls"), isOn: $plugin.showLanguageControls)
                        .onChange(of: plugin.showLanguageControls) { _, _ in onSave() }

                    Text(String(localized: "When enabled, source and target language selectors appear in the result panel header."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Action buttons
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Result Actions"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(String(localized: "Copy"), isOn: Binding(
                        get: { plugin.enabledActions.contains(.copy) },
                        set: { enabled in
                            if enabled { plugin.enabledActions.insert(.copy) }
                            else { plugin.enabledActions.remove(.copy) }
                            onSave()
                        }
                    ))
                    Toggle(String(localized: "Insert"), isOn: Binding(
                        get: { plugin.enabledActions.contains(.insert) },
                        set: { enabled in
                            if enabled { plugin.enabledActions.insert(.insert) }
                            else { plugin.enabledActions.remove(.insert) }
                            onSave()
                        }
                    ))
                    Toggle(String(localized: "Replace"), isOn: Binding(
                        get: { plugin.enabledActions.contains(.replace) },
                        set: { enabled in
                            if enabled { plugin.enabledActions.insert(.replace) }
                            else { plugin.enabledActions.remove(.replace) }
                            onSave()
                        }
                    ))

                    Text(String(localized: "Choose which action buttons appear at the bottom of the result panel."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Action buttons
                HStack {
                    if plugin.isBuiltIn {
                        Button(String(localized: "Reset to Default")) {
                            onReset()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    } else {
                        Button(String(localized: "Delete Plugin"), role: .destructive) {
                            onDelete()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                    Spacer()
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Placeholder Chip

private struct PlaceholderChip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
            }
    }
}
