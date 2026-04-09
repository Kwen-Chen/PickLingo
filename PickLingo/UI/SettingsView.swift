import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(UIString("General"), systemImage: "gear") }
            PluginSettingsView()
                .tabItem { Label(UIString("Plugins"), systemImage: "puzzlepiece") }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 420, idealHeight: 560)
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
    @State private var showingKey = false
    @State private var modelProfileNameDraft: String = ""

    // API Test state
    @State private var isTesting = false
    @State private var testResult: APITestResult?

    private let customProfileTag = "__custom__"

    var body: some View {
        Form {
            // Behavior
            Section {
                Toggle(UIString("Enable PickLingo"), isOn: $settings.isEnabled)

                Toggle(UIString("Auto-detect source language"), isOn: $settings.autoDetectLanguage)

                Toggle(UIString("Launch at login"), isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled: enabled)
                    }

                Picker(UIString("Interface language"), selection: $settings.interfaceLanguage) {
                    Text(UIString("Follow System")).tag(InterfaceLanguage.system)
                    Text("English").tag(InterfaceLanguage.english)
                    Text(UIString("Simplified Chinese")).tag(InterfaceLanguage.simplifiedChinese)
                }

                Picker(UIString("Theme"), selection: $settings.appTheme) {
                    Text(UIString("Follow System")).tag(AppTheme.system)
                    Text(UIString("Light")).tag(AppTheme.light)
                    Text(UIString("Dark")).tag(AppTheme.dark)
                }
            }

            Section {
                Picker(UIString("Default target language"), selection: $settings.defaultTargetLanguage) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.uiName).tag(lang)
                    }
                }

                HStack {
                    Text(UIString("Tooltip delay"))
                    Slider(value: $settings.tooltipDelay, in: 0.0...2.0, step: 0.1) {
                        Text(UIString("Delay"))
                    }
                    Text(String(format: "%.1fs", settings.tooltipDelay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }

                Toggle(UIString("Auto-hide tooltip when mouse moves away"), isOn: $settings.tooltipAutoDismissByDistanceEnabled)

                if settings.tooltipAutoDismissByDistanceEnabled {
                    HStack {
                        Text(UIString("Tooltip auto-hide distance"))
                        Slider(value: $settings.tooltipDismissDistance, in: 20...400, step: 5) {
                            Text(UIString("Distance"))
                        }
                        Text("\(Int(settings.tooltipDismissDistance))px")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            // API Configuration
            Section(header: Text(UIString("OpenAI API"))) {
                Text(UIString("API Key, Base URL, and Model are saved together in each preset."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 12) {
                    // Left: preset list
                    VStack(alignment: .leading, spacing: 8) {
                        Text(UIString("Presets"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                presetRow(id: customProfileTag, title: UIString("Custom (unsaved)"))
                                ForEach(settings.modelProfiles) { profile in
                                    presetRow(id: profile.id, title: profile.name)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 220)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        }

                        Button(UIString("New custom draft")) {
                            settings.clearSelectedModelProfile()
                            modelProfileNameDraft = UIString("My preset")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(width: 180, alignment: .topLeading)

                    // Right: editor panel
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(UIString("Preset name"), text: $modelProfileNameDraft)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            if showingKey {
                                TextField(UIString("API Key"), text: $settings.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField(UIString("API Key"), text: $settings.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(action: { showingKey.toggle() }) {
                                Image(systemName: showingKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                        .onChange(of: settings.apiKey) { _, _ in
                            PluginExecutor.shared.refreshService()
                            testResult = nil
                        }

                        TextField(UIString("API Base URL"), text: $settings.apiBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.apiBaseURL) { _, _ in
                                testResult = nil
                            }

                        TextField(UIString("Model"), text: $settings.apiModel)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.apiModel) { _, _ in
                                testResult = nil
                            }

                        HStack(spacing: 8) {
                            Spacer()

                            Button(UIString("Save")) {
                                saveAsNewPreset()
                            }
                            .disabled(!canSaveAsNewPreset)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(UIString("Update")) {
                                updateSelectedPreset()
                            }
                            .disabled(!canUpdateSelectedPreset)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(UIString("Delete"), role: .destructive) {
                                settings.deleteSelectedModelProfile()
                                syncPresetDraft()
                            }
                            .disabled(settings.selectedModelProfile == nil)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        HStack(spacing: 8) {
                            Spacer()

                            Button(action: testAPIConnection) {
                                HStack(spacing: 4) {
                                    if isTesting {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 10))
                                    }
                                    Text(UIString("Test Connection"))
                                        .font(.system(size: 12))
                                }
                            }
                            .disabled(isTesting || settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if let result = testResult {
                                testResultLabel(result)
                            }

                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            Section(header: Text(UIString("Streaming & Think Mode"))) {
                Toggle(UIString("Enable streaming output"), isOn: $settings.streamingEnabled)

                Toggle(UIString("Enable Think Mode"), isOn: $settings.thinkModeEnabled)
                    .disabled(!settings.streamingEnabled)

                if !settings.streamingEnabled {
                    Text(UIString("Think Mode requires streaming to be enabled."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text(UIString("App Scope"))) {
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
        .padding()
        .onAppear {
            syncLaunchAtLoginSettingFromSystem()
            if !settings.selectedModelProfileID.isEmpty {
                settings.applyModelProfile(id: settings.selectedModelProfileID)
            }
            syncPresetDraft()
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

    private func presetRow(id: String, title: String) -> some View {
        let isSelected = (settings.selectedModelProfileID.isEmpty && id == customProfileTag) || settings.selectedModelProfileID == id
        return Button {
            if id == customProfileTag {
                settings.clearSelectedModelProfile()
            } else {
                settings.applyModelProfile(id: id)
            }
            PluginExecutor.shared.refreshService()
            syncPresetDraft()
            testResult = nil
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
            }
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("\(message) (\(String(format: "%.1fs", latency)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .failure(let message, let latency):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text("\(message) (\(String(format: "%.1fs", latency)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
