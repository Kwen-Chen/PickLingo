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
                Text(UIString("Plugins"))
                    .font(.headline)
                Spacer()
                Button(action: addNewPlugin) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help(UIString("Add new plugin"))
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
                Button(UIString("Reset All")) {
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
            .alert(UIString("Delete Plugin?"), isPresented: $showingDeleteConfirmation) {
                Button(UIString("Delete"), role: .destructive) {
                    if let p = pluginToDelete {
                        selectedPluginID = nil
                        pluginManager.deletePlugin(p)
                    }
                }
                Button(UIString("Cancel"), role: .cancel) {}
            } message: {
                Text(UIString("This plugin will be permanently removed."))
            }
        } else {
            VStack {
                Spacer()
                Text(UIString("Select a plugin to edit"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func addNewPlugin() {
        let newPlugin = Plugin(
            id: UUID(),
            name: UIString("New Plugin"),
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

            Text(plugin.uiDisplayName)
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
    @State private var iconSearchText: String = ""
    @State private var showingIconPicker: Bool = false

    // Common SF Symbol names for the picker
    private let commonIcons = [
        "translate", "globe", "network", "link", "safari",
        "book", "character.book.closed", "text.book.closed", "newspaper",
        "doc.text", "doc.on.doc", "doc.badge.plus", "folder", "folder.badge.plus",
        "folder.badge.magnifyingglass", "externaldrive", "externaldrive.badge.plus",
        "magnifyingglass", "magnifyingglass.circle", "binoculars", "line.3.horizontal.decrease.circle",
        "bubble.left.and.text.bubble.right", "message", "message.badge", "ellipsis.bubble",
        "wand.and.stars", "sparkles", "magicmouse", "paintbrush", "highlighter",
        "pencil", "pencil.and.outline", "square.and.pencil", "lasso",
        "brain.head.profile", "lightbulb", "bolt", "flame", "target",
        "text.quote", "text.alignleft", "textformat", "textformat.abc", "abc",
        "list.bullet", "checklist", "checkmark.circle", "text.badge.checkmark",
        "square.and.arrow.up", "square.and.arrow.down", "arrow.triangle.2.circlepath", "arrow.clockwise",
        "scissors", "paperclip", "bookmark", "bookmark.circle", "tag",
        "calendar", "clock", "timer", "bell", "bell.badge",
        "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces", "hammer",
        "wrench.and.screwdriver", "gear", "gearshape", "slider.horizontal.3",
        "lock", "lock.open", "key", "shield", "checkmark.shield",
        "person", "person.2", "person.crop.circle", "person.badge.key",
        "star", "star.fill", "heart", "flag", "pin",
    ]

    private var filteredIcons: [String] {
        let keyword = iconSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return commonIcons }
        return commonIcons.filter { $0.lowercased().contains(keyword) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(UIString("Name"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(UIString("Plugin name"), text: $plugin.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: plugin.name) { _, _ in onSave() }
                }

                // Icon
                VStack(alignment: .leading, spacing: 4) {
                    Text(UIString("Icon"))
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

                        Button {
                            showingIconPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: plugin.icon)
                                Text(plugin.icon)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField(UIString("Search icons"), text: $iconSearchText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 12)
                                    .padding(.top, 12)

                                ScrollView {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                                        ForEach(filteredIcons, id: \.self) { icon in
                                            Button {
                                                plugin.icon = icon
                                                onSave()
                                                showingIconPicker = false
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: icon)
                                                        .frame(width: 16)
                                                    Text(icon)
                                                        .font(.system(size: 11))
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                    Spacer(minLength: 0)
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 6)
                                                .background {
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .fill(plugin.icon == icon ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 12)
                                }
                            }
                            .frame(width: 380, height: 300)
                        }

                        Spacer()
                    }
                }

                // Execution mode
                VStack(alignment: .leading, spacing: 4) {
                    Text(UIString("Execution"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $plugin.executionMode) {
                        Text(UIString("AI")).tag(PluginExecutionMode.ai)
                        Text(UIString("Local Action")).tag(PluginExecutionMode.localAction)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: plugin.executionMode) { _, newValue in
                        if newValue == .localAction {
                            if plugin.localCommandTemplate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                                plugin.localCommandTemplate = "open {selected_text}"
                            }
                        }
                        onSave()
                    }
                }

                if plugin.executionMode == .localAction {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(UIString("Local Command"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: Binding(
                            get: { plugin.localCommandTemplate ?? "" },
                            set: { newValue in
                                plugin.localCommandTemplate = newValue
                                onSave()
                            }
                        ))
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
                        .frame(minHeight: 84)

                        Text(UIString("Example: open {selected_text}"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(UIString("Placeholders: {selected_text}, {user_input}, {source}, {target}"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Toggle(UIString("Show result window"), isOn: $plugin.showResultPanel)
                            .onChange(of: plugin.showResultPanel) { _, _ in onSave() }

                        Text(UIString("When disabled, the local action runs without opening the result window. Errors are still shown."))
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Toggle(UIString("Requires user input"), isOn: $plugin.needsUserInput)
                            .onChange(of: plugin.needsUserInput) { _, _ in onSave() }

                        if plugin.needsUserInput {
                            TextField(
                                UIString("Input placeholder"),
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
                } else {
                    // Prompt
                    VStack(alignment: .leading, spacing: 4) {
                        Text(UIString("System Prompt"))
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
                            Text(UIString("Placeholders:"))
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
                        Toggle(UIString("Requires user input"), isOn: $plugin.needsUserInput)
                            .onChange(of: plugin.needsUserInput) { _, _ in onSave() }

                        if plugin.needsUserInput {
                            TextField(
                                UIString("Input placeholder"),
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
                        Toggle(UIString("Show source/target language controls"), isOn: $plugin.showLanguageControls)
                            .onChange(of: plugin.showLanguageControls) { _, _ in onSave() }

                        Text(UIString("When enabled, source and target language selectors appear in the result panel header."))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Action buttons
                    VStack(alignment: .leading, spacing: 4) {
                        Text(UIString("Result Actions"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle(UIString("Copy"), isOn: Binding(
                            get: { plugin.enabledActions.contains(.copy) },
                            set: { enabled in
                                if enabled { plugin.enabledActions.insert(.copy) }
                                else { plugin.enabledActions.remove(.copy) }
                                onSave()
                            }
                        ))
                        Toggle(UIString("Insert"), isOn: Binding(
                            get: { plugin.enabledActions.contains(.insert) },
                            set: { enabled in
                                if enabled { plugin.enabledActions.insert(.insert) }
                                else { plugin.enabledActions.remove(.insert) }
                                onSave()
                            }
                        ))
                        Toggle(UIString("Replace"), isOn: Binding(
                            get: { plugin.enabledActions.contains(.replace) },
                            set: { enabled in
                                if enabled { plugin.enabledActions.insert(.replace) }
                                else { plugin.enabledActions.remove(.replace) }
                                onSave()
                            }
                        ))
                        Toggle(UIString("Regenerate"), isOn: Binding(
                            get: { plugin.enabledActions.contains(.regenerate) },
                            set: { enabled in
                                if enabled { plugin.enabledActions.insert(.regenerate) }
                                else { plugin.enabledActions.remove(.regenerate) }
                                onSave()
                            }
                        ))
                        Toggle(UIString("Follow-up"), isOn: Binding(
                            get: { plugin.enabledActions.contains(.followUp) },
                            set: { enabled in
                                if enabled { plugin.enabledActions.insert(.followUp) }
                                else { plugin.enabledActions.remove(.followUp) }
                                onSave()
                            }
                        ))

                        Text(UIString("Choose which action buttons appear at the bottom of the result panel."))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()

                // Action buttons
                HStack {
                    if plugin.isBuiltIn {
                        Button(UIString("Reset to Default")) {
                            onReset()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    } else {
                        Button(UIString("Delete Plugin"), role: .destructive) {
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
