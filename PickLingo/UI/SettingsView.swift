import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedPage: SettingsPage = .general
    @State private var modelProfileNameDraft = ""
    @State private var selectedPluginID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(UIString(selectedPage.title))
                        .font(.system(size: 24, weight: .bold))
                    Text(UIString(selectedPage.subtitle))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)

                Divider()

                switch selectedPage {
                case .general:
                    GeneralSettingsTab(modelProfileNameDraft: $modelProfileNameDraft)
                case .plugins:
                    PluginSettingsView(selectedPluginID: $selectedPluginID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .textSelection(.enabled)
        }
        .frame(minWidth: 860, idealWidth: 960, minHeight: 560, idealHeight: 700)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PickLingo")
                        .font(.system(size: 15, weight: .semibold))
                    Text(UIString("Settings"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 6) {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        selectedPage = page
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.icon)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 22)
                            Text(UIString(page.title))
                                .font(.system(size: 13, weight: selectedPage == page ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedPage == page ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(selectedPage == page ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPage == page ? [.isSelected] : [])
                }
            }

            Spacer()

            Text("PickLingo \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 24)
        .frame(width: 172)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general, plugins

    var id: String { rawValue }
    var title: String { self == .general ? "General" : "Plugins" }
    var icon: String { self == .general ? "slider.horizontal.3" : "puzzlepiece.extension" }
    var subtitle: String {
        self == .general
            ? "Make PickLingo work your way."
            : "Customize the tools that appear when you select text."
    }
}

private struct SettingsSectionTitle: View {
    let title: String
    let icon: String

    var body: some View {
        Label(UIString(title), systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .labelStyle(.titleAndIcon)
    }
}

private struct TooltipAppearanceSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section(header: SettingsSectionTitle(title: "Selection Toolbar", icon: "cursorarrow.rays")) {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(TooltipStyle.allCases) { style in styleCard(style) }
                }

                HStack {
                    Text(UIString("Toolbar position"))
                    Spacer()
                    Picker(UIString("Toolbar position"), selection: $settings.tooltipPosition) {
                        ForEach(TooltipPosition.allCases) { position in
                            Text(UIString(position.title)).tag(position)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    .textSelection(.disabled)
                }

                settingSlider("Plugin spacing", value: $settings.tooltipPluginSpacing,
                              range: AppSettings.tooltipPluginSpacingRange)
                settingSlider("Horizontal offset", value: $settings.tooltipHorizontalOffset,
                              range: AppSettings.tooltipHorizontalOffsetRange, lower: "Left", upper: "Right")
                settingSlider("Vertical gap", value: $settings.tooltipVerticalGap,
                              range: AppSettings.tooltipVerticalGapRange, lower: "Near", upper: "Far")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(UIString("Position preview"))
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button(UIString("Reset position")) {
                            settings.tooltipHorizontalOffset = 0
                            settings.tooltipVerticalGap = 12
                            settings.tooltipPosition = .below
                        }
                        .controlSize(.small)
                        .textSelection(.disabled)
                    }
                    ToolbarPositionPreview(style: settings.tooltipStyle, spacing: settings.tooltipPluginSpacing,
                                           horizontalOffset: settings.tooltipHorizontalOffset,
                                           verticalGap: settings.tooltipVerticalGap, position: settings.tooltipPosition)
                    Text(UIString("Appearance and position update as you adjust the controls."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UIString("Position may flip near the edge of the screen."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(UIString("Select this text to try the toolbar."))
                    .font(.callout)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("PickLingoSelectionSample")
            }
            .padding(.vertical, 6)

            HStack {
                Text(UIString("Tooltip delay"))
                Slider(value: Binding(get: { settings.tooltipDelay },
                                      set: { settings.tooltipDelay = ($0 * 10).rounded() / 10 }), in: 0...2)
                    .labelsHidden()
                    .accessibilityLabel(UIString("Tooltip delay"))
                Text(String(format: "%.1fs", settings.tooltipDelay))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            Toggle(UIString("Auto-hide tooltip when mouse moves away"), isOn: $settings.tooltipAutoDismissByDistanceEnabled)
                .textSelection(.disabled)
            if settings.tooltipAutoDismissByDistanceEnabled {
                HStack {
                    Text(UIString("Tooltip auto-hide distance"))
                    Slider(value: Binding(get: { settings.tooltipDismissDistance },
                                          set: { settings.tooltipDismissDistance = ($0 / 5).rounded() * 5 }), in: 20...400)
                        .labelsHidden()
                        .accessibilityLabel(UIString("Tooltip auto-hide distance"))
                    Text("\(Int(settings.tooltipDismissDistance))px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private func styleCard(_ style: TooltipStyle) -> some View {
        let selected = settings.tooltipStyle == style
        return Button {
            settings.tooltipStyle = style
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(UIString(style.title))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.3))
                }
                TooltipBarView(plugins: Array(Plugin.defaultPlugins.prefix(3)), style: style,
                               spacing: 4, maximumWidth: 300, onSelect: { _ in })
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .allowsHitTesting(false)
            }
            .padding(12)
            .background(selected ? Color.accentColor.opacity(0.055) : Color.primary.opacity(0.02),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.07), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .textSelection(.disabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UIString(style.title))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                               lower: String? = nil, upper: String? = nil) -> some View {
        HStack(spacing: 10) {
            Text(UIString(title))
                .frame(width: 108, alignment: .leading)
            if let lower { Text(UIString(lower)).font(.caption).foregroundStyle(.tertiary) }
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() }), in: range)
                .labelsHidden()
                .accessibilityLabel(UIString(title))
            if let upper { Text(UIString(upper)).font(.caption).foregroundStyle(.tertiary) }
            Text("\(Int(value.wrappedValue)) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

struct ToolbarPositionPreview: View {
    var style: TooltipStyle
    var spacing: Double
    var horizontalOffset: Double
    var verticalGap: Double
    var position: TooltipPosition

    var body: some View {
        GeometryReader { proxy in
            ToolbarPreviewLayout(horizontalOffset: horizontalOffset, verticalGap: verticalGap, position: position) {
                Text(UIString("Selected text"))
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.17), in: RoundedRectangle(cornerRadius: 4))
                TooltipBarView(plugins: Array(Plugin.defaultPlugins.prefix(4)), style: style, spacing: spacing,
                               maximumWidth: max(80, proxy.size.width - 32), onSelect: { _ in })
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 300)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.025))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ToolbarPreviewLayout: Layout {
    let horizontalOffset: Double
    let verticalGap: Double
    let position: TooltipPosition

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 500, height: proposal.height ?? 300)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let textSize = subviews[0].sizeThatFits(.unspecified)
        let selection = CGRect(x: bounds.width / 2 - textSize.width / 2, y: bounds.height / 2 - textSize.height / 2,
                               width: textSize.width, height: textSize.height)
        let toolbarSize = subviews[1].sizeThatFits(.unspecified)
        let toolbar = ScreenLocator.toolbarFrame(
            for: toolbarSize, selectionBounds: selection, anchor: CGPoint(x: selection.midX, y: selection.midY),
            horizontalOffset: horizontalOffset, verticalGap: verticalGap, position: position,
            in: CGRect(origin: .zero, size: bounds.size)
        )
        // Convert shared bottom-left placement coordinates to SwiftUI's top-left.
        for (index, frame) in [selection, toolbar].enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + bounds.height - frame.maxY),
                                  anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

private struct BlacklistedAppItem: Identifiable {
    let id: String
    let name: String
    let bundleID: String
}

// MARK: - General Settings (includes API config)

struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var selectionMonitor = AccessibilityMonitor.shared
    @State private var showingKey = false
    @Binding var modelProfileNameDraft: String

    // API Test state
    @State private var isTesting = false
    @State private var testResult: APITestResult?

    private let customProfileTag = "__custom__"

    private var selectionStatusText: String {
        switch selectionMonitor.monitoringState {
        case .active: return "Selection monitoring is active."
        case .disabled: return "Selection monitoring is off."
        case .permissionRequired: return "Accessibility permission is required for text selection."
        case .unavailable: return "Selection monitoring could not start."
        }
    }

    private var selectionStatusIcon: String {
        switch selectionMonitor.monitoringState {
        case .active: return "checkmark.circle.fill"
        case .disabled: return "pause.circle"
        case .permissionRequired, .unavailable: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.isEnabled) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(UIString("Enable PickLingo"))
                            .font(.system(size: 14, weight: .semibold))
                        Label(UIString(selectionStatusText), systemImage: selectionStatusIcon)
                            .font(.caption)
                            .foregroundStyle(selectionMonitor.monitoringState == .active ? Color.green : Color.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .textSelection(.disabled)
                if selectionMonitor.monitoringState == .permissionRequired {
                    Button(String(localized: "Open Accessibility Settings")) {
                        selectionMonitor.requestAccessibility()
                    }
                } else if selectionMonitor.monitoringState == .unavailable {
                    Button(UIString("Restart Selection Monitoring")) {
                        selectionMonitor.startMonitoring(restart: true)
                    }
                }
                Toggle(UIString("Launch at login"), isOn: $settings.launchAtLogin)
                .textSelection(.disabled)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled: enabled)
                    }
            }

            apiConfigurationSection

            Section(header: SettingsSectionTitle(title: "Interface", icon: "paintpalette")) {
                Picker(UIString("Interface language"), selection: $settings.interfaceLanguage) {
                    Text(UIString("Follow System")).tag(InterfaceLanguage.system)
                    Text("English").tag(InterfaceLanguage.english)
                    Text(UIString("Simplified Chinese")).tag(InterfaceLanguage.simplifiedChinese)
                }
                .textSelection(.disabled)

                Picker(UIString("Theme"), selection: $settings.appTheme) {
                    Text(UIString("Follow System")).tag(AppTheme.system)
                    Text(UIString("Light")).tag(AppTheme.light)
                    Text(UIString("Dark")).tag(AppTheme.dark)
                }
                .textSelection(.disabled)
                .pickerStyle(.segmented)
            }

            Section(header: SettingsSectionTitle(title: "Translation", icon: "character.bubble")) {
                Toggle(UIString("Auto-detect source language"), isOn: $settings.autoDetectLanguage)
                .textSelection(.disabled)
                Picker(UIString("Default target language"), selection: $settings.defaultTargetLanguage) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.uiName).tag(lang)
                    }
                }
                .textSelection(.disabled)
            }

            TooltipAppearanceSettings()

            Section(header: SettingsSectionTitle(title: "Result Panel", icon: "text.alignleft")) {
                HStack {
                    Text(UIString("Result panel font size"))
                    Slider(value: $settings.resultPanelFontSize, in: AppSettings.resultPanelFontSizeRange, step: 1)
                    Text("\(Int(settings.resultPanelFontSize))pt")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                Text(UIString("Preview result panel text"))
                    .font(.system(size: CGFloat(settings.resultPanelFontSize)))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }

            Section(header: SettingsSectionTitle(title: "Quick Ask", icon: "bolt.bubble")) {
                Toggle(UIString("Enable Quick Ask shortcut"), isOn: $settings.quickAskEnabled)
                .textSelection(.disabled)

                HStack(spacing: 8) {
                    Text(UIString("Quick Ask shortcut"))
                    TextField(QuickAskShortcutParser.defaultShortcut, text: $settings.quickAskShortcut)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!settings.quickAskEnabled)
                        .onSubmit {
                            settings.quickAskShortcut = QuickAskShortcutParser.normalize(settings.quickAskShortcut)
                        }
                }

                if QuickAskShortcutParser.parse(settings.quickAskShortcut) == nil {
                    Text(UIString("This shortcut is invalid or reserved for editing. Try cmd+shift+k."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text(UIString("Use cmd+cmd for double-Command tap, or shortcuts like cmd+shift+k."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(UIString("Quick Ask prompt"))
                        Spacer()
                        Button(UIString("Reset to Default")) {
                            settings.quickAskPrompt = AppSettings.defaultQuickAskPrompt
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!settings.quickAskEnabled)
                    }

                    TextEditor(text: $settings.quickAskPrompt)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 90)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        }
                        .disabled(!settings.quickAskEnabled)

                    Text(UIString("Use {user_input} where the typed question should be inserted."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: SettingsSectionTitle(title: "Streaming & Think Mode", icon: "sparkles")) {
                Toggle(UIString("Enable streaming output"), isOn: $settings.streamingEnabled)
                .textSelection(.disabled)

                Toggle(UIString("Enable Think Mode"), isOn: $settings.thinkModeEnabled)
                .textSelection(.disabled)

                Text(UIString("Think Mode uses standard reasoning_effort on supported reasoning models. The service may return only the final answer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: SettingsSectionTitle(title: "App Scope", icon: "app.badge.checkmark")) {
                Text(UIString("PickLingo is enabled in all apps by default. Add apps to the blacklist below to disable it only in those apps. Changes apply immediately when that app is frontmost."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(UIString("Add App to Blacklist")) {
                        presentAppBlacklistPicker()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }

                if blacklistedAppItems.isEmpty {
                    Text(UIString("No blacklisted apps yet. Add an app to exclude PickLingo from it."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(blacklistedAppItems) { item in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.system(size: 13, weight: .medium))
                                        Text(item.bundleID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    Spacer()

                                    Button(UIString("Remove")) {
                                        settings.setAppBlacklisted(false, for: item.bundleID)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .toggleStyle(.switch)
        .controlSize(.regular)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .onAppear {
            syncLaunchAtLoginSettingFromSystem()
            if modelProfileNameDraft.isEmpty { syncPresetDraft() }
        }
    }

    private var canSaveAsNewPreset: Bool {
        let trimmedName = modelProfileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty &&
            !settings.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !settings.apiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canUpdateSelectedPreset: Bool {
        guard settings.selectedModelProfile != nil else { return false }
        return canSaveAsNewPreset
    }

    // API Configuration
    private var apiConfigurationSection: some View {
        Section(header: SettingsSectionTitle(title: "OpenAI API", icon: "network")) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Picker(UIString("Presets"), selection: Binding(
                        get: { settings.selectedModelProfileID.isEmpty ? customProfileTag : settings.selectedModelProfileID },
                        set: { selectPreset(id: $0) }
                    )) {
                        Text(UIString("Custom (unsaved)")).tag(customProfileTag)
                        ForEach(settings.modelProfiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .textSelection(.disabled)
                    .frame(maxWidth: .infinity)

                    Button {
                        selectPreset(id: customProfileTag)
                    } label: {
                        Label(UIString("New custom draft"), systemImage: "plus")
                    }
                    .controlSize(.small)
                }

                Divider()

                apiField("Preset name") {
                    TextField(UIString("Preset name"), text: $modelProfileNameDraft)
                        .labelsHidden()
                }

                apiField("API Key") {
                    HStack(spacing: 8) {
                        Group {
                            if showingKey {
                                TextField(UIString("API Key"), text: $settings.apiKey)
                            } else {
                                SecureField(UIString("API Key"), text: $settings.apiKey)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("PickLingoSensitiveField")
                        Button { showingKey.toggle() } label: {
                            Image(systemName: showingKey ? "eye.slash" : "eye")
                                .frame(width: 20)
                        }
                        .buttonStyle(.borderless)
                        .help(UIString(showingKey ? "Hide API key" : "Show API key"))
                        .accessibilityLabel(UIString(showingKey ? "Hide API key" : "Show API key"))
                    }
                    .onChange(of: settings.apiKey) { _, _ in
                        PluginExecutor.shared.refreshService()
                        testResult = nil
                    }
                }

                apiField("API Base URL") {
                    TextField(UIString("API Base URL"), text: $settings.apiBaseURL)
                        .labelsHidden()
                        .onChange(of: settings.apiBaseURL) { _, _ in testResult = nil }
                }

                apiField("Model") {
                    TextField(UIString("Model"), text: $settings.apiModel)
                        .labelsHidden()
                        .onChange(of: settings.apiModel) { _, _ in testResult = nil }
                }

                Text(UIString("API Key, Base URL, and Model are saved together in each preset."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(UIString("Save"), action: saveAsNewPreset)
                        .disabled(!canSaveAsNewPreset)
                    Button(UIString("Update"), action: updateSelectedPreset)
                        .disabled(!canUpdateSelectedPreset)
                    Button(UIString("Delete"), role: .destructive) {
                        settings.deleteSelectedModelProfile()
                        syncPresetDraft()
                    }
                    .disabled(settings.selectedModelProfile == nil)

                    Spacer(minLength: 12)

                    Button(action: testAPIConnection) {
                        HStack(spacing: 6) {
                            if isTesting {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(UIString("Test Connection"))
                        }
                    }
                    .disabled(isTesting || settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let result = testResult {
                    testResultLabel(result)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 6)
        }
    }

    private func apiField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(UIString(title))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectPreset(id: String) {
        if id == customProfileTag {
            settings.clearSelectedModelProfile()
        } else {
            settings.applyModelProfile(id: id)
        }
        PluginExecutor.shared.refreshService()
        syncPresetDraft()
        testResult = nil
    }

    private var blacklistedAppItems: [BlacklistedAppItem] {
        settings.appEnabledOverrides.keys
            .map { bundleID in
                BlacklistedAppItem(
                    id: bundleID,
                    name: displayName(for: bundleID),
                    bundleID: bundleID
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else {
            return bundleID
        }

        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }

        return FileManager.default.displayName(atPath: url.path)
    }

    private func presentAppBlacklistPicker() {
        let panel = NSOpenPanel()
        panel.title = UIString("Choose Apps to Blacklist")
        panel.message = UIString("Selected apps will be added to the blacklist and PickLingo will stay disabled in them.")
        panel.prompt = UIString("Add to Blacklist")
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]

        if panel.runModal() == .OK {
            for url in panel.urls {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !bundleID.isEmpty else { continue }
                settings.setAppBlacklisted(true, for: bundleID)
            }
        }
    }

    private func syncPresetDraft() {
        if let selected = settings.selectedModelProfile {
            modelProfileNameDraft = selected.name
        } else {
            modelProfileNameDraft = UIString("My preset")
        }
    }

    private func saveAsNewPreset() {
        guard canSaveAsNewPreset else { return }
        settings.addModelProfile(
            name: modelProfileNameDraft,
            baseURL: settings.apiBaseURL,
            model: settings.apiModel,
            apiKey: settings.apiKey
        )
        syncPresetDraft()
    }

    private func updateSelectedPreset() {
        guard canUpdateSelectedPreset else { return }
        settings.updateSelectedModelProfile(
            name: modelProfileNameDraft,
            baseURL: settings.apiBaseURL,
            model: settings.apiModel,
            apiKey: settings.apiKey
        )
        syncPresetDraft()
    }

    // MARK: - Test Connection

    private func testAPIConnection() {
        isTesting = true
        testResult = nil

        Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            do {
                let service = OpenAIService()
                let reply = try await service.execute(
                    systemPrompt: "Reply with exactly: OK",
                    userMessage: "Test"
                )
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                await MainActor.run {
                    isTesting = false
                    testResult = .success(
                        message: reply.prefix(50).trimmingCharacters(in: .whitespacesAndNewlines),
                        latency: elapsed
                    )
                }
            } catch {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                await MainActor.run {
                    isTesting = false
                    testResult = .failure(
                        message: error.localizedDescription,
                        latency: elapsed
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func testResultLabel(_ result: APITestResult) -> some View {
        switch result {
        case .success(let message, let latency):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("\(message) (\(String(format: "%.1fs", latency)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case .failure(let message, let latency):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text("\(message) (\(String(format: "%.1fs", latency)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert UI to the real current state if registration fails.
            syncLaunchAtLoginSettingFromSystem()
            print("[PickLingo] Failed to update launch-at-login: \(error.localizedDescription)")
        }
    }

    private func syncLaunchAtLoginSettingFromSystem() {
        let status = SMAppService.mainApp.status
        settings.launchAtLogin = (status == .enabled)
    }
}

// MARK: - API Test Result

enum APITestResult {
    case success(message: String, latency: Double)
    case failure(message: String, latency: Double)
}
