import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(String(localized: "General"), systemImage: "gear") }
            PluginSettingsView()
                .tabItem { Label(String(localized: "Plugins"), systemImage: "puzzlepiece") }
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 400, idealHeight: 520)
    }
}

private struct AppScopeItem: Identifiable {
    let id: String
    let name: String
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
                Toggle(String(localized: "Enable PickLingo"), isOn: $settings.isEnabled)

                Toggle(String(localized: "Auto-detect source language"), isOn: $settings.autoDetectLanguage)

                Toggle(String(localized: "Launch at login"), isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled: enabled)
                    }
            }

            Section {
                Picker(String(localized: "Default target language"), selection: $settings.defaultTargetLanguage) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.nativeName).tag(lang)
                    }
                }

                HStack {
                    Text(String(localized: "Tooltip delay"))
                    Slider(value: $settings.tooltipDelay, in: 0.1...2.0, step: 0.1) {
                        Text("Delay")
                    }
                    Text(String(format: "%.1fs", settings.tooltipDelay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }

                Toggle(String(localized: "Auto-hide tooltip when mouse moves away"), isOn: $settings.tooltipAutoDismissByDistanceEnabled)

                if settings.tooltipAutoDismissByDistanceEnabled {
                    HStack {
                        Text(String(localized: "Tooltip auto-hide distance"))
                        Slider(value: $settings.tooltipDismissDistance, in: 20...400, step: 5) {
                            Text("Distance")
                        }
                        Text("\(Int(settings.tooltipDismissDistance))px")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            // API Configuration
            Section(header: Text("OpenAI API")) {
                Text(String(localized: "API Key, Base URL, and Model are saved together in each preset."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 12) {
                    // Left: preset list
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Presets"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                presetRow(id: customProfileTag, title: String(localized: "Custom (unsaved)"))
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

                        Button(String(localized: "New custom draft")) {
                            settings.clearSelectedModelProfile()
                            modelProfileNameDraft = String(localized: "My preset")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(width: 180, alignment: .topLeading)

                    // Right: editor panel
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(String(localized: "Preset name"), text: $modelProfileNameDraft)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            if showingKey {
                                TextField("API Key", text: $settings.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("API Key", text: $settings.apiKey)
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

                        TextField(String(localized: "API Base URL"), text: $settings.apiBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.apiBaseURL) { _, _ in
                                testResult = nil
                            }

                        TextField(String(localized: "Model"), text: $settings.apiModel)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.apiModel) { _, _ in
                                testResult = nil
                            }

                        HStack(spacing: 8) {
                            Button(String(localized: "Save as new preset")) {
                                saveAsNewPreset()
                            }
                            .disabled(!canSaveAsNewPreset)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(String(localized: "Update selected preset")) {
                                updateSelectedPreset()
                            }
                            .disabled(!canUpdateSelectedPreset)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(String(localized: "Delete selected preset"), role: .destructive) {
                                settings.deleteSelectedModelProfile()
                                syncPresetDraft()
                            }
                            .disabled(settings.selectedModelProfile == nil)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        HStack(spacing: 8) {
                            Button(action: testAPIConnection) {
                                HStack(spacing: 4) {
                                    if isTesting {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 10))
                                    }
                                    Text(String(localized: "Test Connection"))
                                        .font(.system(size: 12))
                                }
                            }
                            .disabled(isTesting || settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if let result = testResult {
                                testResultLabel(result)
                            }

                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            Section(header: Text(String(localized: "Streaming & Think Mode"))) {
                Toggle(String(localized: "Enable streaming output"), isOn: $settings.streamingEnabled)

                Toggle(String(localized: "Enable Think Mode"), isOn: $settings.thinkModeEnabled)
                    .disabled(!settings.streamingEnabled)

                if !settings.streamingEnabled {
                    Text(String(localized: "Think Mode requires streaming to be enabled."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text(String(localized: "App Scope"))) {
                Text(String(localized: "Turn PickLingo on or off for each app. Changes apply immediately when that app is frontmost."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appScopeItems.isEmpty {
                    Text(String(localized: "No running apps detected. Open target apps and come back to configure them."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appScopeItems) { item in
                                Toggle(item.name, isOn: appScopeBinding(for: item.id))
                                    .toggleStyle(.switch)
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

    private var appScopeItems: [AppScopeItem] {
        var seen: Set<String> = []
        let apps = NSWorkspace.shared.runningApplications
            .compactMap { app -> AppScopeItem? in
                guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return nil }
                guard app.activationPolicy == .regular else { return nil }
                if seen.contains(bundleID) { return nil }
                seen.insert(bundleID)
                return AppScopeItem(id: bundleID, name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps
    }

    private func appScopeBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { settings.isAppEnabled(bundleID: bundleID) },
            set: { enabled in settings.setAppEnabled(enabled, for: bundleID) }
        )
    }

    private func syncPresetDraft() {
        if let selected = settings.selectedModelProfile {
            modelProfileNameDraft = selected.name
        } else {
            modelProfileNameDraft = String(localized: "My preset")
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
