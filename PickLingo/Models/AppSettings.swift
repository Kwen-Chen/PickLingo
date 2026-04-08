import Foundation
import Combine

struct ModelProfile: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var baseURL: String
    var model: String
    var apiKey: String

    init(id: String = UUID().uuidString, name: String, baseURL: String, model: String, apiKey: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var isEnabled: Bool = true { didSet { persistIfNeeded() } }
    @Published var autoDetectLanguage: Bool = true { didSet { persistIfNeeded() } }
    @Published var defaultTargetLanguage: Language = .chinese { didSet { persistIfNeeded() } }
    @Published var tooltipDelay: Double = 0.0 { didSet { persistIfNeeded() } }
    @Published var apiBaseURL: String = "https://api.openai.com" { didSet { persistIfNeeded() } }
    @Published var apiModel: String = "gpt-4o-mini" { didSet { persistIfNeeded() } }
    @Published var apiKey: String = "" { didSet { persistIfNeeded() } }
    @Published var launchAtLogin: Bool = false { didSet { persistIfNeeded() } }
    @Published var streamingEnabled: Bool = true { didSet { persistIfNeeded() } }
    @Published var thinkModeEnabled: Bool = false { didSet { persistIfNeeded() } }
    @Published var tooltipAutoDismissByDistanceEnabled: Bool = false { didSet { persistIfNeeded() } }
    @Published var tooltipDismissDistance: Double = 100 { didSet { persistIfNeeded() } }
    @Published var selectedModelProfileID: String = "" { didSet { persistIfNeeded() } }

    @Published private(set) var modelProfiles: [ModelProfile] = [] { didSet { persistIfNeeded() } }
    @Published private(set) var appEnabledOverrides: [String: Bool] = [:] { didSet { persistIfNeeded() } }

    private struct PersistedSettings: Codable {
        var isEnabled: Bool
        var autoDetectLanguage: Bool
        var defaultTargetLanguage: Language
        var tooltipDelay: Double
        var apiBaseURL: String
        var apiModel: String
        var apiKey: String
        var launchAtLogin: Bool
        var streamingEnabled: Bool
        var thinkModeEnabled: Bool
        var tooltipAutoDismissByDistanceEnabled: Bool
        var tooltipDismissDistance: Double
        var selectedModelProfileID: String
        var modelProfiles: [ModelProfile]
        var appEnabledOverrides: [String: Bool]

        init(
            isEnabled: Bool,
            autoDetectLanguage: Bool,
            defaultTargetLanguage: Language,
            tooltipDelay: Double,
            apiBaseURL: String,
            apiModel: String,
            apiKey: String,
            launchAtLogin: Bool,
            streamingEnabled: Bool,
            thinkModeEnabled: Bool,
            tooltipAutoDismissByDistanceEnabled: Bool,
            tooltipDismissDistance: Double,
            selectedModelProfileID: String,
            modelProfiles: [ModelProfile],
            appEnabledOverrides: [String: Bool]
        ) {
            self.isEnabled = isEnabled
            self.autoDetectLanguage = autoDetectLanguage
            self.defaultTargetLanguage = defaultTargetLanguage
            self.tooltipDelay = tooltipDelay
            self.apiBaseURL = apiBaseURL
            self.apiModel = apiModel
            self.apiKey = apiKey
            self.launchAtLogin = launchAtLogin
            self.streamingEnabled = streamingEnabled
            self.thinkModeEnabled = thinkModeEnabled
            self.tooltipAutoDismissByDistanceEnabled = tooltipAutoDismissByDistanceEnabled
            self.tooltipDismissDistance = tooltipDismissDistance
            self.selectedModelProfileID = selectedModelProfileID
            self.modelProfiles = modelProfiles
            self.appEnabledOverrides = appEnabledOverrides
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
            autoDetectLanguage = try c.decode(Bool.self, forKey: .autoDetectLanguage)
            defaultTargetLanguage = try c.decode(Language.self, forKey: .defaultTargetLanguage)
            tooltipDelay = try c.decode(Double.self, forKey: .tooltipDelay)
            apiBaseURL = try c.decode(String.self, forKey: .apiBaseURL)
            apiModel = try c.decode(String.self, forKey: .apiModel)
            apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
            launchAtLogin = try c.decode(Bool.self, forKey: .launchAtLogin)
            streamingEnabled = try c.decode(Bool.self, forKey: .streamingEnabled)
            thinkModeEnabled = try c.decode(Bool.self, forKey: .thinkModeEnabled)
            tooltipAutoDismissByDistanceEnabled = try c.decode(Bool.self, forKey: .tooltipAutoDismissByDistanceEnabled)
            tooltipDismissDistance = try c.decode(Double.self, forKey: .tooltipDismissDistance)
            selectedModelProfileID = try c.decode(String.self, forKey: .selectedModelProfileID)
            modelProfiles = try c.decode([ModelProfile].self, forKey: .modelProfiles)
            appEnabledOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .appEnabledOverrides) ?? [:]
        }
    }

    private static var configDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".picklingo", isDirectory: true)
    }

    private static var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("config.json")
    }

    private var suppressPersistence = false

    private init() {
        load()
    }

    // MARK: - Model Profiles

    var selectedModelProfile: ModelProfile? {
        guard !selectedModelProfileID.isEmpty else { return nil }
        return modelProfiles.first(where: { $0.id == selectedModelProfileID })
    }

    func addModelProfile(name: String, baseURL: String, model: String, apiKey: String) {
        let profile = ModelProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelProfiles.append(profile)
        selectedModelProfileID = profile.id
    }

    func updateSelectedModelProfile(name: String, baseURL: String, model: String, apiKey: String) {
        guard let index = modelProfiles.firstIndex(where: { $0.id == selectedModelProfileID }) else { return }
        modelProfiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        modelProfiles[index].baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        modelProfiles[index].model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        modelProfiles[index].apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deleteSelectedModelProfile() {
        guard !selectedModelProfileID.isEmpty else { return }
        modelProfiles.removeAll { $0.id == selectedModelProfileID }
        selectedModelProfileID = ""
    }

    func applyModelProfile(id: String) {
        guard let profile = modelProfiles.first(where: { $0.id == id }) else { return }
        selectedModelProfileID = id
        apiBaseURL = profile.baseURL
        apiModel = profile.model
        apiKey = profile.apiKey
    }

    func clearSelectedModelProfile() {
        selectedModelProfileID = ""
    }

    func syncProfileSelectionWithCurrentModel() {
        if let matched = modelProfiles.first(where: {
            $0.baseURL == apiBaseURL && $0.model == apiModel && $0.apiKey == apiKey
        }) {
            selectedModelProfileID = matched.id
        } else {
            selectedModelProfileID = ""
        }
    }

    // MARK: - App Filters

    func isAppEnabled(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return true }
        return appEnabledOverrides[bundleID] ?? true
    }

    func setAppEnabled(_ enabled: Bool, for bundleID: String) {
        appEnabledOverrides[bundleID] = enabled
    }

    // MARK: - Persistence

    private func persistIfNeeded() {
        guard !suppressPersistence else { return }
        save()
    }

    private func save() {
        let persisted = PersistedSettings(
            isEnabled: isEnabled,
            autoDetectLanguage: autoDetectLanguage,
            defaultTargetLanguage: defaultTargetLanguage,
            tooltipDelay: tooltipDelay,
            apiBaseURL: apiBaseURL,
            apiModel: apiModel,
            apiKey: apiKey,
            launchAtLogin: launchAtLogin,
            streamingEnabled: streamingEnabled,
            thinkModeEnabled: thinkModeEnabled,
            tooltipAutoDismissByDistanceEnabled: tooltipAutoDismissByDistanceEnabled,
            tooltipDismissDistance: tooltipDismissDistance,
            selectedModelProfileID: selectedModelProfileID,
            modelProfiles: modelProfiles,
            appEnabledOverrides: appEnabledOverrides
        )

        do {
            try FileManager.default.createDirectory(at: Self.configDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(persisted)
            try data.write(to: Self.configFileURL, options: .atomic)
        } catch {
            print("[PickLingo] Failed to save settings: \(error)")
        }
    }

    private func load() {
        suppressPersistence = true
        defer { suppressPersistence = false }

        if let data = try? Data(contentsOf: Self.configFileURL),
           let persisted = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            isEnabled = persisted.isEnabled
            autoDetectLanguage = persisted.autoDetectLanguage
            defaultTargetLanguage = persisted.defaultTargetLanguage
            tooltipDelay = persisted.tooltipDelay
            apiBaseURL = persisted.apiBaseURL
            apiModel = persisted.apiModel
            apiKey = persisted.apiKey
            launchAtLogin = persisted.launchAtLogin
            streamingEnabled = persisted.streamingEnabled
            thinkModeEnabled = persisted.thinkModeEnabled
            tooltipAutoDismissByDistanceEnabled = persisted.tooltipAutoDismissByDistanceEnabled
            tooltipDismissDistance = persisted.tooltipDismissDistance
            selectedModelProfileID = persisted.selectedModelProfileID
            modelProfiles = persisted.modelProfiles
            appEnabledOverrides = persisted.appEnabledOverrides
            return
        }

        // One-time migration from previous UserDefaults-based storage.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "isEnabled") != nil { isEnabled = defaults.bool(forKey: "isEnabled") }
        if defaults.object(forKey: "autoDetectLanguage") != nil { autoDetectLanguage = defaults.bool(forKey: "autoDetectLanguage") }
        if let raw = defaults.string(forKey: "defaultTargetLanguage"), let lang = Language(rawValue: raw) {
            defaultTargetLanguage = lang
        }
        if defaults.object(forKey: "tooltipDelay") != nil { tooltipDelay = defaults.double(forKey: "tooltipDelay") }
        if let value = defaults.string(forKey: "apiBaseURL"), !value.isEmpty { apiBaseURL = value }
        if let value = defaults.string(forKey: "apiModel"), !value.isEmpty { apiModel = value }
        if let legacyKey = KeychainHelper.load(key: "openai_api_key"), !legacyKey.isEmpty {
            apiKey = legacyKey
        }
        if defaults.object(forKey: "launchAtLogin") != nil { launchAtLogin = defaults.bool(forKey: "launchAtLogin") }
        if defaults.object(forKey: "streamingEnabled") != nil { streamingEnabled = defaults.bool(forKey: "streamingEnabled") }
        if defaults.object(forKey: "thinkModeEnabled") != nil { thinkModeEnabled = defaults.bool(forKey: "thinkModeEnabled") }
        if defaults.object(forKey: "tooltipAutoDismissByDistanceEnabled") != nil {
            tooltipAutoDismissByDistanceEnabled = defaults.bool(forKey: "tooltipAutoDismissByDistanceEnabled")
        }
        if defaults.object(forKey: "tooltipDismissDistance") != nil {
            tooltipDismissDistance = defaults.double(forKey: "tooltipDismissDistance")
        }
        if let value = defaults.string(forKey: "selectedModelProfileID") {
            selectedModelProfileID = value
        }
        if let data = defaults.data(forKey: "modelProfiles"),
           let decoded = try? JSONDecoder().decode([ModelProfile].self, from: data) {
            modelProfiles = decoded
        }
        if let raw = defaults.dictionary(forKey: "appEnabledOverrides") {
            appEnabledOverrides = raw.compactMapValues { $0 as? Bool }
        }

        save()
    }
}
