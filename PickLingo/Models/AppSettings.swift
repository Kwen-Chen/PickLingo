import Foundation
import Combine
import AppKit

enum InterfaceLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var effectiveLanguage: InterfaceLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

struct UILocalizer {
    private typealias Pair = (en: String, zhHans: String)

    private static let manualTranslations: [String: Pair] = [
        "General": ("General", "通用"),
        "Plugins": ("Plugins", "插件"),
        "Interface language": ("Interface language", "界面语言"),
        "Theme": ("Theme", "主题"),
        "Light": ("Light", "浅色"),
        "Dark": ("Dark", "深色"),
        "Follow System": ("Follow System", "跟随系统"),
        "Simplified Chinese": ("Simplified Chinese", "简体中文"),
        "Enable PickLingo": ("Enable PickLingo", "启用 PickLingo"),
        "Disable PickLingo": ("Disable PickLingo", "禁用 PickLingo"),
        "Settings…": ("Settings…", "设置…"),
        "Quit PickLingo": ("Quit PickLingo", "退出 PickLingo"),
        "PickLingo Settings": ("PickLingo Settings", "PickLingo 设置"),
        "Auto-detect source language": ("Auto-detect source language", "自动检测源语言"),
        "Launch at login": ("Launch at login", "开机启动"),
        "Default target language": ("Default target language", "默认目标语言"),
        "Tooltip delay": ("Tooltip delay", "提示延迟"),
        "Delay": ("Delay", "延迟"),
        "Auto-hide tooltip when mouse moves away": ("Auto-hide tooltip when mouse moves away", "鼠标移开后自动隐藏提示"),
        "Tooltip auto-hide distance": ("Tooltip auto-hide distance", "提示自动隐藏距离"),
        "Distance": ("Distance", "距离"),
        "OpenAI API": ("OpenAI API", "OpenAI API"),
        "API Key, Base URL, and Model are saved together in each preset.": ("API Key, Base URL, and Model are saved together in each preset.", "API Key、Base URL 和 Model 会一起保存到每个预设。"),
        "Presets": ("Presets", "预设"),
        "Custom (unsaved)": ("Custom (unsaved)", "自定义（未保存）"),
        "New custom draft": ("New custom draft", "新建草稿"),
        "My preset": ("My preset", "我的预设"),
        "Preset name": ("Preset name", "预设名称"),
        "API Key": ("API Key", "API 密钥"),
        "API Base URL": ("API Base URL", "API 基础 URL"),
        "Model": ("Model", "模型"),
        "Save": ("Save", "保存"),
        "Update": ("Update", "更新"),
        "Delete": ("Delete", "删除"),
        "Test Connection": ("Test Connection", "测试连接"),
        "Streaming & Think Mode": ("Streaming & Think Mode", "流式输出与 Think 模式"),
        "Enable streaming output": ("Enable streaming output", "启用流式输出"),
        "Enable Think Mode": ("Enable Think Mode", "启用 Think 模式"),
        "Think Mode requires streaming to be enabled.": ("Think Mode requires streaming to be enabled.", "Think 模式依赖流式输出，请先开启流式输出。"),
        "App Scope": ("App Scope", "应用范围"),
        "PickLingo is enabled in all apps by default. Add apps to the blacklist below to disable it only in those apps. Changes apply immediately when that app is frontmost.": ("PickLingo is enabled in all apps by default. Add apps to the blacklist below to disable it only in those apps. Changes apply immediately when that app is frontmost.", "PickLingo 默认在所有应用中启用。将应用加入下方黑名单后，仅在这些应用中禁用。切到该应用时立即生效。"),
        "Add App to Blacklist": ("Add App to Blacklist", "添加应用到黑名单"),
        "No blacklisted apps yet. Add an app to exclude PickLingo from it.": ("No blacklisted apps yet. Add an app to exclude PickLingo from it.", "暂无黑名单应用，添加后可在该应用中禁用 PickLingo。"),
        "Remove": ("Remove", "移除"),
        "Choose Apps to Blacklist": ("Choose Apps to Blacklist", "选择要加入黑名单的应用"),
        "Selected apps will be added to the blacklist and PickLingo will stay disabled in them.": ("Selected apps will be added to the blacklist and PickLingo will stay disabled in them.", "所选应用会被加入黑名单，PickLingo 将在这些应用中保持禁用。"),
        "Add to Blacklist": ("Add to Blacklist", "加入黑名单"),
        "Add new plugin": ("Add new plugin", "添加新插件"),
        "Reset All": ("Reset All", "重置全部"),
        "Delete Plugin?": ("Delete Plugin?", "删除插件？"),
        "Cancel": ("Cancel", "取消"),
        "This plugin will be permanently removed.": ("This plugin will be permanently removed.", "该插件将被永久删除。"),
        "Select a plugin to edit": ("Select a plugin to edit", "选择一个插件进行编辑"),
        "New Plugin": ("New Plugin", "新插件"),
        "Name": ("Name", "名称"),
        "Plugin name": ("Plugin name", "插件名称"),
        "Icon": ("Icon", "图标"),
        "System Prompt": ("System Prompt", "系统提示词"),
        "Placeholders:": ("Placeholders:", "占位符："),
        "Requires user input": ("Requires user input", "需要用户输入"),
        "Input placeholder": ("Input placeholder", "输入占位提示"),
        "Show source/target language controls": ("Show source/target language controls", "显示源语言/目标语言控制"),
        "When enabled, source and target language selectors appear in the result panel header.": ("When enabled, source and target language selectors appear in the result panel header.", "启用后，结果面板顶部会显示源语言和目标语言选择器。"),
        "Result Actions": ("Result Actions", "结果操作"),
        "Copy": ("Copy", "复制"),
        "Insert": ("Insert", "插入"),
        "Replace": ("Replace", "替换"),
        "Regenerate": ("Regenerate", "重新生成"),
        "Follow-up": ("Follow-up", "追问"),
        "Type your follow-up...": ("Type your follow-up...", "输入你的追问..."),
        "Type your question...": ("Type your question...", "输入你的问题..."),
        "Choose which action buttons appear at the bottom of the result panel.": ("Choose which action buttons appear at the bottom of the result panel.", "选择结果面板底部要显示的操作按钮。"),
        "Reset to Default": ("Reset to Default", "恢复默认"),
        "Delete Plugin": ("Delete Plugin", "删除插件"),
        "Thinking…": ("Thinking…", "思考中…"),
        "Processing…": ("Processing…", "处理中…"),
        "Translating…": ("Translating…", "翻译中…"),
        "Pin panel": ("Pin panel", "固定面板"),
        "Unpin panel": ("Unpin panel", "取消固定"),
        "Translate": ("Translate", "翻译"),
        "Explain": ("Explain", "解释"),
        "Polish": ("Polish", "润色"),
        "Summarize": ("Summarize", "总结"),
        "Ask": ("Ask", "提问"),
        "English": ("English", "英语"),
        "Chinese": ("Chinese", "中文"),
        "Japanese": ("Japanese", "日语"),
        "Korean": ("Korean", "韩语"),
        "French": ("French", "法语"),
        "German": ("German", "德语"),
        "Spanish": ("Spanish", "西班牙语"),
        "Russian": ("Russian", "俄语"),
        "Portuguese": ("Portuguese", "葡萄牙语"),
        "Arabic": ("Arabic", "阿拉伯语")
    ]

    static func text(_ key: String) -> String {
        let preferred = AppSettings.shared.interfaceLanguage.effectiveLanguage
        if let pair = manualTranslations[key] {
            return preferred == .simplifiedChinese ? pair.zhHans : pair.en
        }

        switch preferred {
        case .english:
            return localizedFromBundle(key, languageCode: "en")
        case .simplifiedChinese:
            return localizedFromBundle(key, languageCode: "zh-Hans")
        case .system:
            return localizedFromBundle(key, languageCode: "en")
        }
    }

    private static func localizedFromBundle(_ key: String, languageCode: String) -> String {
        guard
            let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }

        let value = bundle.localizedString(forKey: key, value: key, table: nil)
        if value != key {
            return value
        }
        if let pair = manualTranslations[key] {
            return languageCode == "zh-Hans" ? pair.zhHans : pair.en
        }
        return NSLocalizedString(key, comment: "")
    }
}

@inline(__always)
func UIString(_ key: String) -> String {
    UILocalizer.text(key)
}

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
    @Published var interfaceLanguage: InterfaceLanguage = .system { didSet { persistIfNeeded() } }
    @Published var appTheme: AppTheme = .system { didSet { persistIfNeeded() } }

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
        var interfaceLanguage: InterfaceLanguage
        var appTheme: AppTheme
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
            interfaceLanguage: InterfaceLanguage,
            appTheme: AppTheme,
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
            self.interfaceLanguage = interfaceLanguage
            self.appTheme = appTheme
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
            interfaceLanguage = try c.decodeIfPresent(InterfaceLanguage.self, forKey: .interfaceLanguage) ?? .system
            appTheme = try c.decodeIfPresent(AppTheme.self, forKey: .appTheme) ?? .system
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
        return !(appEnabledOverrides[bundleID] ?? false)
    }

    func setAppEnabled(_ enabled: Bool, for bundleID: String) {
        if enabled {
            appEnabledOverrides.removeValue(forKey: bundleID)
        } else {
            appEnabledOverrides[bundleID] = true
        }
    }

    func isAppBlacklisted(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return appEnabledOverrides[bundleID] ?? false
    }

    func setAppBlacklisted(_ blacklisted: Bool, for bundleID: String) {
        if blacklisted {
            appEnabledOverrides[bundleID] = true
        } else {
            appEnabledOverrides.removeValue(forKey: bundleID)
        }
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
            interfaceLanguage: interfaceLanguage,
            appTheme: appTheme,
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
            interfaceLanguage = persisted.interfaceLanguage
            appTheme = persisted.appTheme
            modelProfiles = persisted.modelProfiles
            appEnabledOverrides = persisted.appEnabledOverrides.reduce(into: [:]) { result, entry in
                if entry.value == false {
                    result[entry.key] = true
                }
            }
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
        if let raw = defaults.string(forKey: "interfaceLanguage"),
           let language = InterfaceLanguage(rawValue: raw) {
            interfaceLanguage = language
        }
        if let raw = defaults.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: raw) {
            appTheme = theme
        }
        if let data = defaults.data(forKey: "modelProfiles"),
           let decoded = try? JSONDecoder().decode([ModelProfile].self, from: data) {
            modelProfiles = decoded
        }
        if let raw = defaults.dictionary(forKey: "appEnabledOverrides") {
            let decoded = raw.compactMapValues { $0 as? Bool }
            appEnabledOverrides = decoded.reduce(into: [:]) { result, entry in
                if entry.value == false {
                    result[entry.key] = true
                }
            }
        }

        save()
    }
}
