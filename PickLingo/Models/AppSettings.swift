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

enum QuickAskShortcutTrigger: Equatable {
    case doubleCommandTap
    case keyCombo(key: String, modifiers: NSEvent.ModifierFlags)
}

struct QuickAskShortcutParser {
    static let defaultShortcut = "cmd+cmd"

    static func parse(_ rawValue: String) -> QuickAskShortcutTrigger? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "")
        guard let trigger = parseWithoutNormalization(value) else { return nil }
        // These native editing shortcuts must never open a window over the source app.
        if case .keyCombo(let key, let modifiers) = trigger,
           modifiers == .command, ["c", "v", "x", "a", "z"].contains(key) { return nil }
        return trigger
    }

    static func normalize(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return defaultShortcut }
        guard let parsed = parse(trimmed) else { return trimmed }
        return serialize(parsed)
    }

    private static func parseWithoutNormalization(_ normalized: String) -> QuickAskShortcutTrigger? {
        if normalized == defaultShortcut {
            return .doubleCommandTap
        }

        let tokens = normalized
            .split(separator: "+")
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard tokens.count >= 2, !normalized.contains("++"),
              !normalized.hasPrefix("+"), !normalized.hasSuffix("+") else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        var keyToken: String?
        for token in tokens {
            switch token {
            case "cmd", "command", "⌘":
                modifiers.insert(.command)
            case "shift", "⇧":
                modifiers.insert(.shift)
            case "opt", "option", "alt", "⌥":
                modifiers.insert(.option)
            case "ctrl", "control", "⌃":
                modifiers.insert(.control)
            default:
                guard keyToken == nil else { return nil }
                keyToken = token
            }
        }
        guard let keyToken, let key = canonicalKeyToken(keyToken), !modifiers.isEmpty else {
            return nil
        }
        return .keyCombo(key: key, modifiers: modifiers)
    }

    private static func serialize(_ trigger: QuickAskShortcutTrigger) -> String {
        switch trigger {
        case .doubleCommandTap:
            return defaultShortcut
        case .keyCombo(let key, let modifiers):
            var parts: [String] = []
            if modifiers.contains(.command) { parts.append("cmd") }
            if modifiers.contains(.control) { parts.append("ctrl") }
            if modifiers.contains(.option) { parts.append("opt") }
            if modifiers.contains(.shift) { parts.append("shift") }
            parts.append(key)
            return parts.joined(separator: "+")
        }
    }

    private static func canonicalKeyToken(_ token: String) -> String? {
        switch token {
        case "space", "spacebar":
            return "space"
        case "return", "enter":
            return "return"
        case "tab":
            return "tab"
        case "esc", "escape":
            return "escape"
        default:
            guard token.count == 1 else { return nil }
            guard let scalar = token.unicodeScalars.first else { return nil }
            let allowed = CharacterSet.alphanumerics
            return allowed.contains(scalar) ? token : nil
        }
    }
}

struct UILocalizer {
    private typealias Pair = (en: String, zhHans: String)

    private static let manualTranslations: [String: Pair] = [
        "Selection Monitoring": ("Selection Monitoring", "选区监听"),
        "Selection monitoring is active.": ("Selection monitoring is active.", "选区监听已启动。"),
        "Selection monitoring is off.": ("Selection monitoring is off.", "选区监听已关闭。"),
        "Accessibility permission is required for text selection.": ("Accessibility permission is required for text selection.", "缺少辅助功能权限，无法读取选中文字。"),
        "Selection monitoring could not start.": ("Selection monitoring could not start.", "选区监听启动失败，正在重试。"),
        "Selection detection resumes automatically after Accessibility permission is granted.": ("Selection detection resumes automatically after Accessibility permission is granted.", "授予辅助功能权限后会自动恢复选区监听，无需重启应用。"),
        "Restart Selection Monitoring": ("Restart Selection Monitoring", "重新启动选区监听"),
        "Enter an API model name.": ("Enter an API model name.", "请输入 API 模型名称。"),
        "Think Mode uses standard reasoning_effort on supported reasoning models. The service may return only the final answer.": ("Think Mode uses standard reasoning_effort on supported reasoning models. The service may return only the final answer.", "Think Mode 使用标准 reasoning_effort 参数，需要支持推理的模型。服务可能仅返回最终回答。"),
        "Enter a valid HTTP or HTTPS API base URL.": ("Enter a valid HTTP or HTTPS API base URL.", "请输入有效的 HTTP 或 HTTPS API 基础 URL。"),
        "Menu Bar": ("Menu Bar", "菜单栏"),
        "Open macOS Menu Bar Settings": ("Open macOS Menu Bar Settings", "打开 macOS 菜单栏设置"),
        "If the icon is missing, allow PickLingo in macOS Menu Bar settings. Reopen the app from Finder or Spotlight to access this window.": ("If the icon is missing, allow PickLingo in macOS Menu Bar settings. Reopen the app from Finder or Spotlight to access this window.", "若图标未显示，请在 macOS 菜单栏设置中允许 PickLingo 显示。也可从 Finder 或 Spotlight 再次打开应用，进入此设置窗口。"),
        "Process Copied Text": ("Process Copied Text", "处理已复制文本"),
        "Disable in Current App": ("Disable in Current App", "在当前应用中禁用"),
        "Selection & Clipboard": ("Selection & Clipboard", "选中与剪贴板"),
        "Automatic selection detection never copies or restores your clipboard.": ("Automatic selection detection never copies or restores your clipboard.", "自动取词不会执行复制，也不会恢复或覆盖你的剪贴板。"),
        "If an app does not expose selected text, copy normally, then choose Process Copied Text from the menu bar.": ("If an app does not expose selected text, copy normally, then choose Process Copied Text from the menu bar.", "若某个应用无法自动取词，请正常复制，再从菜单栏选择“处理已复制文本”。"),
        "Insert and Replace leave the result on the clipboard.": ("Insert and Replace leave the result on the clipboard.", "插入和替换会将结果保留在剪贴板中。"),
        "This shortcut is invalid or reserved for editing. Try cmd+shift+k.": ("This shortcut is invalid or reserved for editing. Try cmd+shift+k.", "快捷键无效或与系统编辑操作冲突，请尝试 cmd+shift+k。"),
        "Source app unavailable. Copy the result and paste it manually.": ("Source app unavailable. Copy the result and paste it manually.", "源应用无法激活，请复制结果后手动粘贴。"),
        "Paste canceled because the app or clipboard changed. Copy the result and paste it manually.": ("Paste canceled because the app or clipboard changed. Copy the result and paste it manually.", "应用或剪贴板已变化，已取消粘贴。请复制结果后手动粘贴。"),
        "Copy All (⇧⌘C)": ("Copy All (⇧⌘C)", "复制全部（⇧⌘C）"),
        "Stop": ("Stop", "停止"),

        "General": ("General", "通用"),
        "Plugins": ("Plugins", "插件"),
        "Settings": ("Settings", "设置"),
        "Position may flip near the edge of the screen.": ("Position may flip near the edge of the screen.", "靠近屏幕边缘时会自动避让，保持工具栏完整可见。"),
        "Reset position": ("Reset position", "重置位置"),
        "Appearance and position update as you adjust the controls.": ("Appearance and position update as you adjust the controls.", "样式、间距和位置会随调整实时更新。"),
        "Selected text": ("Selected text", "选中的文字"),
        "Position preview": ("Position preview", "位置预览"),
        "Far": ("Far", "远"),
        "Near": ("Near", "近"),
        "Right": ("Right", "向右"),
        "Left": ("Left", "向左"),
        "Vertical gap": ("Vertical gap", "垂直间距"),
        "Horizontal offset": ("Horizontal offset", "水平偏移"),
        "Above text": ("Above text", "文字上方"),
        "Below text": ("Below text", "文字下方"),
        "Toolbar position": ("Toolbar position", "弹出位置"),
        "Close": ("Close", "关闭"),
        "Minimize": ("Minimize", "最小化"),
        "Window": ("Window", "窗口"),
        "Select All": ("Select All", "全选"),
        "Paste": ("Paste", "粘贴"),
        "Cut": ("Cut", "剪切"),
        "Redo": ("Redo", "重做"),
        "Undo": ("Undo", "撤销"),
        "Edit": ("Edit", "编辑"),
        "Select this text to try the toolbar.": ("Select this text to try the toolbar.", "选中这段文字，试试弹出工具栏。"),
        "Live preview": ("Live preview", "实时预览"),
        "Icon and text": ("Icon and text", "图文卡片"),
        "Minimal bar": ("Minimal bar", "墨色极简"),
        "Frosted capsule": ("Frosted capsule", "磨砂胶囊"),
        "Floating circles": ("Floating circles", "悬浮圆钮"),
        "Plugin spacing": ("Plugin spacing", "插件间距"),
        "Toolbar style": ("Toolbar style", "工具栏样式"),
        "Selection Toolbar": ("Selection Toolbar", "选中工具栏"),
        "Make PickLingo work your way.": ("Make PickLingo work your way.", "按你的习惯，调整 PickLingo。"),
        "Customize the tools that appear when you select text.": ("Customize the tools that appear when you select text.", "定制选中文字后使用的工具。"),
        "Show API key": ("Show API key", "显示 API 密钥"),
        "Hide API key": ("Hide API key", "隐藏 API 密钥"),
        "General Behavior": ("General Behavior", "基本行为"),
        "Interface": ("Interface", "界面"),
        "Translation": ("Translation", "翻译"),
        "Tooltip": ("Tooltip", "提示"),
        "Result Panel": ("Result Panel", "结果面板"),
        "Preview result panel text": ("Preview result panel text", "结果面板字体预览"),
        "Interface language": ("Interface language", "界面语言"),
        "Theme": ("Theme", "主题"),
        "Result panel font size": ("Result panel font size", "结果面板字体大小"),
        "Font size": ("Font size", "字体大小"),
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
        "Quick Ask": ("Quick Ask", "快速提问"),
        "Enable Quick Ask shortcut": ("Enable Quick Ask shortcut", "启用快速提问快捷键"),
        "Quick Ask shortcut": ("Quick Ask shortcut", "快速提问快捷键"),
        "Use cmd+cmd for double-Command tap, or shortcuts like cmd+shift+k.": ("Use cmd+cmd for double-Command tap, or shortcuts like cmd+shift+k.", "使用 cmd+cmd 表示双击 Command，或设置为 cmd+shift+k 这类快捷键。"),
        "Quick Ask prompt": ("Quick Ask prompt", "快速提问提示词"),
        "Use {user_input} where the typed question should be inserted.": ("Use {user_input} where the typed question should be inserted.", "使用 {user_input} 表示输入的问题插入位置。"),
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
        "Show result window": ("Show result window", "显示结果窗口"),
        "When disabled, the local action runs without opening the result window. Errors are still shown.": ("When disabled, the local action runs without opening the result window. Errors are still shown.", "关闭后，本地操作会直接执行，不打开结果窗口；错误仍会显示。"),
        "Local Action Failed": ("Local Action Failed", "本地操作失败"),
        "OK": ("OK", "确定"),
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
        "Open Folder": ("Open Folder", "打开目录"),
        "Search": ("Search", "搜索"),
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

enum TooltipStyle: String, CaseIterable, Codable, Identifiable {
    case floating, capsule, minimal, labeled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .floating: return "Floating circles"
        case .capsule: return "Frosted capsule"
        case .minimal: return "Minimal bar"
        case .labeled: return "Icon and text"
        }
    }
}

enum TooltipPosition: String, CaseIterable, Codable, Identifiable {
    case below, above
    var id: String { rawValue }
    var title: String { self == .below ? "Below text" : "Above text" }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let tooltipHorizontalOffsetRange: ClosedRange<Double> = -120...120
    static let tooltipVerticalGapRange: ClosedRange<Double> = 0...80
    static func sanitizedTooltipHorizontalOffset(_ value: Double) -> Double {
        value.isFinite ? min(120, max(-120, value)) : 0
    }
    static func sanitizedTooltipVerticalGap(_ value: Double) -> Double {
        value.isFinite ? min(80, max(0, value)) : 12
    }
    static let tooltipPluginSpacingRange: ClosedRange<Double> = 0...24
    static func sanitizedTooltipSpacing(_ value: Double) -> Double {
        value.isFinite ? min(24, max(0, value)) : 2
    }
    static let resultPanelFontSizeRange: ClosedRange<Double> = 11...22
    static let defaultQuickAskPrompt = """
    Answer the user's question thoughtfully and accurately.

    Question:
    {user_input}
    """

    @Published var isEnabled: Bool = true { didSet { persistIfNeeded() } }
    @Published var autoDetectLanguage: Bool = true { didSet { persistIfNeeded() } }
    @Published var defaultTargetLanguage: Language = .chinese { didSet { persistIfNeeded() } }
    @Published var tooltipPosition: TooltipPosition = .below { didSet { persistIfNeeded() } }
    @Published var tooltipHorizontalOffset: Double = 0 {
        didSet {
            let value = Self.sanitizedTooltipHorizontalOffset(tooltipHorizontalOffset)
            if value != tooltipHorizontalOffset { tooltipHorizontalOffset = value }
            persistIfNeeded()
        }
    }
    @Published var tooltipVerticalGap: Double = 12 {
        didSet {
            let value = Self.sanitizedTooltipVerticalGap(tooltipVerticalGap)
            if value != tooltipVerticalGap { tooltipVerticalGap = value }
            persistIfNeeded()
        }
    }
    @Published var tooltipStyle: TooltipStyle = .floating { didSet { persistIfNeeded() } }
    @Published var tooltipPluginSpacing: Double = 2 {
        didSet {
            let value = Self.sanitizedTooltipSpacing(tooltipPluginSpacing)
            if value != tooltipPluginSpacing { tooltipPluginSpacing = value }
            persistIfNeeded()
        }
    }
    @Published var tooltipDelay: Double = 0.0 { didSet { persistIfNeeded() } }
    @Published var apiBaseURL: String = "https://api.openai.com" { didSet { persistIfNeeded() } }
    @Published var apiModel: String = "gpt-4o-mini" { didSet { persistIfNeeded() } }
    @Published var apiKey: String = "" { didSet { persistIfNeeded() } }
    @Published var launchAtLogin: Bool = false { didSet { persistIfNeeded() } }
    @Published var streamingEnabled: Bool = true { didSet { persistIfNeeded() } }
    @Published var thinkModeEnabled: Bool = false { didSet { persistIfNeeded() } }
    @Published var tooltipAutoDismissByDistanceEnabled: Bool = false { didSet { persistIfNeeded() } }
    @Published var tooltipDismissDistance: Double = 100 { didSet { persistIfNeeded() } }
    @Published var quickAskEnabled: Bool = true { didSet { persistIfNeeded() } }
    @Published var quickAskShortcut: String = QuickAskShortcutParser.defaultShortcut { didSet { persistIfNeeded() } }
    @Published var quickAskPrompt: String = AppSettings.defaultQuickAskPrompt { didSet { persistIfNeeded() } }
    @Published var selectedModelProfileID: String = "" { didSet { persistIfNeeded() } }
    @Published var interfaceLanguage: InterfaceLanguage = .system { didSet { persistIfNeeded() } }
    @Published var appTheme: AppTheme = .system { didSet { persistIfNeeded() } }
    @Published var resultPanelFontSize: Double = 13 {
        didSet {
            let clamped = Self.sanitizedResultPanelFontSize(resultPanelFontSize)
            if clamped != resultPanelFontSize {
                resultPanelFontSize = clamped
                return
            }
            persistIfNeeded()
        }
    }

    @Published private(set) var modelProfiles: [ModelProfile] = [] { didSet { persistIfNeeded() } }
    @Published private(set) var appEnabledOverrides: [String: Bool] = [:] { didSet { persistIfNeeded() } }

    private struct PersistedSettings: Codable {
        var isEnabled: Bool
        var autoDetectLanguage: Bool
        var defaultTargetLanguage: Language
        var tooltipPosition: TooltipPosition
        var tooltipHorizontalOffset: Double
        var tooltipVerticalGap: Double
        var tooltipStyle: TooltipStyle
        var tooltipPluginSpacing: Double
        var tooltipDelay: Double
        var apiBaseURL: String
        var apiModel: String
        var apiKey: String
        var launchAtLogin: Bool
        var streamingEnabled: Bool
        var thinkModeEnabled: Bool
        var tooltipAutoDismissByDistanceEnabled: Bool
        var tooltipDismissDistance: Double
        var quickAskEnabled: Bool
        var quickAskShortcut: String
        var quickAskPrompt: String
        var selectedModelProfileID: String
        var interfaceLanguage: InterfaceLanguage
        var appTheme: AppTheme
        var resultPanelFontSize: Double
        var modelProfiles: [ModelProfile]
        var appEnabledOverrides: [String: Bool]

        init(
            isEnabled: Bool,
            autoDetectLanguage: Bool,
            defaultTargetLanguage: Language,
            tooltipPosition: TooltipPosition,
            tooltipHorizontalOffset: Double,
            tooltipVerticalGap: Double,
            tooltipStyle: TooltipStyle,
            tooltipPluginSpacing: Double,
            tooltipDelay: Double,
            apiBaseURL: String,
            apiModel: String,
            apiKey: String,
            launchAtLogin: Bool,
            streamingEnabled: Bool,
            thinkModeEnabled: Bool,
            tooltipAutoDismissByDistanceEnabled: Bool,
            tooltipDismissDistance: Double,
            quickAskEnabled: Bool,
            quickAskShortcut: String,
            quickAskPrompt: String,
            selectedModelProfileID: String,
            interfaceLanguage: InterfaceLanguage,
            appTheme: AppTheme,
            resultPanelFontSize: Double,
            modelProfiles: [ModelProfile],
            appEnabledOverrides: [String: Bool]
        ) {
            self.isEnabled = isEnabled
            self.autoDetectLanguage = autoDetectLanguage
            self.defaultTargetLanguage = defaultTargetLanguage
            self.tooltipPosition = tooltipPosition
            self.tooltipHorizontalOffset = AppSettings.sanitizedTooltipHorizontalOffset(tooltipHorizontalOffset)
            self.tooltipVerticalGap = AppSettings.sanitizedTooltipVerticalGap(tooltipVerticalGap)
            self.tooltipStyle = tooltipStyle
            self.tooltipPluginSpacing = AppSettings.sanitizedTooltipSpacing(tooltipPluginSpacing)
            self.tooltipDelay = tooltipDelay
            self.apiBaseURL = apiBaseURL
            self.apiModel = apiModel
            self.apiKey = apiKey
            self.launchAtLogin = launchAtLogin
            self.streamingEnabled = streamingEnabled
            self.thinkModeEnabled = thinkModeEnabled
            self.tooltipAutoDismissByDistanceEnabled = tooltipAutoDismissByDistanceEnabled
            self.tooltipDismissDistance = tooltipDismissDistance
            self.quickAskEnabled = quickAskEnabled
            self.quickAskShortcut = QuickAskShortcutParser.normalize(quickAskShortcut)
            self.quickAskPrompt = quickAskPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppSettings.defaultQuickAskPrompt
                : quickAskPrompt
            self.selectedModelProfileID = selectedModelProfileID
            self.interfaceLanguage = interfaceLanguage
            self.appTheme = appTheme
            self.resultPanelFontSize = AppSettings.sanitizedResultPanelFontSize(resultPanelFontSize)
            self.modelProfiles = modelProfiles
            self.appEnabledOverrides = appEnabledOverrides
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
            autoDetectLanguage = try c.decode(Bool.self, forKey: .autoDetectLanguage)
            defaultTargetLanguage = try c.decode(Language.self, forKey: .defaultTargetLanguage)
            tooltipPosition = (try c.decodeIfPresent(String.self, forKey: .tooltipPosition)).flatMap(TooltipPosition.init(rawValue:)) ?? .below
            tooltipHorizontalOffset = AppSettings.sanitizedTooltipHorizontalOffset(
                try c.decodeIfPresent(Double.self, forKey: .tooltipHorizontalOffset) ?? 0
            )
            tooltipVerticalGap = AppSettings.sanitizedTooltipVerticalGap(
                try c.decodeIfPresent(Double.self, forKey: .tooltipVerticalGap) ?? 12
            )
            let styleName = try c.decodeIfPresent(String.self, forKey: .tooltipStyle)
            tooltipStyle = styleName.flatMap(TooltipStyle.init(rawValue:)) ?? .floating
            tooltipPluginSpacing = AppSettings.sanitizedTooltipSpacing(
                try c.decodeIfPresent(Double.self, forKey: .tooltipPluginSpacing) ?? 2
            )
            tooltipDelay = try c.decode(Double.self, forKey: .tooltipDelay)
            apiBaseURL = try c.decode(String.self, forKey: .apiBaseURL)
            apiModel = try c.decode(String.self, forKey: .apiModel)
            apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
            launchAtLogin = try c.decode(Bool.self, forKey: .launchAtLogin)
            streamingEnabled = try c.decode(Bool.self, forKey: .streamingEnabled)
            thinkModeEnabled = try c.decode(Bool.self, forKey: .thinkModeEnabled)
            tooltipAutoDismissByDistanceEnabled = try c.decode(Bool.self, forKey: .tooltipAutoDismissByDistanceEnabled)
            tooltipDismissDistance = try c.decode(Double.self, forKey: .tooltipDismissDistance)
            quickAskEnabled = try c.decodeIfPresent(Bool.self, forKey: .quickAskEnabled) ?? true
            quickAskShortcut = QuickAskShortcutParser.normalize(
                try c.decodeIfPresent(String.self, forKey: .quickAskShortcut) ?? QuickAskShortcutParser.defaultShortcut
            )
            let decodedQuickAskPrompt = try c.decodeIfPresent(String.self, forKey: .quickAskPrompt) ?? AppSettings.defaultQuickAskPrompt
            quickAskPrompt = decodedQuickAskPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppSettings.defaultQuickAskPrompt
                : decodedQuickAskPrompt
            selectedModelProfileID = try c.decode(String.self, forKey: .selectedModelProfileID)
            interfaceLanguage = try c.decodeIfPresent(InterfaceLanguage.self, forKey: .interfaceLanguage) ?? .system
            appTheme = try c.decodeIfPresent(AppTheme.self, forKey: .appTheme) ?? .system
            resultPanelFontSize = AppSettings.sanitizedResultPanelFontSize(
                try c.decodeIfPresent(Double.self, forKey: .resultPanelFontSize) ?? 13
            )
            modelProfiles = try c.decode([ModelProfile].self, forKey: .modelProfiles)
            appEnabledOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .appEnabledOverrides) ?? [:]
        }
    }

    private let configDirectoryURL: URL
    private var configFileURL: URL { configDirectoryURL.appendingPathComponent("config.json") }
    private var suppressPersistence = false
    private var saveWorkItem: DispatchWorkItem?
    private var hasPendingChanges = false

    init(configDirectory: URL? = nil) {
        configDirectoryURL = configDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".picklingo", isDirectory: true)
        load(allowLegacyMigration: configDirectory == nil)
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
        hasPendingChanges = true
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func saveImmediately() {
        guard hasPendingChanges else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        save()
    }

    private func save() {
        let persisted = PersistedSettings(
            isEnabled: isEnabled,
            autoDetectLanguage: autoDetectLanguage,
            defaultTargetLanguage: defaultTargetLanguage,
            tooltipPosition: tooltipPosition,
            tooltipHorizontalOffset: tooltipHorizontalOffset,
            tooltipVerticalGap: tooltipVerticalGap,
            tooltipStyle: tooltipStyle,
            tooltipPluginSpacing: tooltipPluginSpacing,
            tooltipDelay: tooltipDelay,
            apiBaseURL: apiBaseURL,
            apiModel: apiModel,
            apiKey: apiKey,
            launchAtLogin: launchAtLogin,
            streamingEnabled: streamingEnabled,
            thinkModeEnabled: thinkModeEnabled,
            tooltipAutoDismissByDistanceEnabled: tooltipAutoDismissByDistanceEnabled,
            tooltipDismissDistance: tooltipDismissDistance,
            quickAskEnabled: quickAskEnabled,
            quickAskShortcut: quickAskShortcut,
            quickAskPrompt: quickAskPrompt,
            selectedModelProfileID: selectedModelProfileID,
            interfaceLanguage: interfaceLanguage,
            appTheme: appTheme,
            resultPanelFontSize: resultPanelFontSize,
            modelProfiles: modelProfiles,
            appEnabledOverrides: appEnabledOverrides
        )

        do {
            try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(persisted)
            try data.write(to: configFileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFileURL.path)
            hasPendingChanges = false
        } catch {
            print("[PickLingo] Failed to save settings: \(error)")
        }
    }

    private func load(allowLegacyMigration: Bool) {
        suppressPersistence = true
        defer { suppressPersistence = false }

        if let data = try? Data(contentsOf: configFileURL),
           let persisted = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            isEnabled = persisted.isEnabled
            autoDetectLanguage = persisted.autoDetectLanguage
            defaultTargetLanguage = persisted.defaultTargetLanguage
            tooltipPosition = persisted.tooltipPosition
            tooltipHorizontalOffset = persisted.tooltipHorizontalOffset
            tooltipVerticalGap = persisted.tooltipVerticalGap
            tooltipStyle = persisted.tooltipStyle
            tooltipPluginSpacing = persisted.tooltipPluginSpacing
            tooltipDelay = persisted.tooltipDelay
            apiBaseURL = persisted.apiBaseURL
            apiModel = persisted.apiModel
            apiKey = persisted.apiKey
            launchAtLogin = persisted.launchAtLogin
            streamingEnabled = persisted.streamingEnabled
            thinkModeEnabled = persisted.thinkModeEnabled
            tooltipAutoDismissByDistanceEnabled = persisted.tooltipAutoDismissByDistanceEnabled
            tooltipDismissDistance = persisted.tooltipDismissDistance
            quickAskEnabled = persisted.quickAskEnabled
            quickAskShortcut = persisted.quickAskShortcut
            quickAskPrompt = persisted.quickAskPrompt
            selectedModelProfileID = persisted.selectedModelProfileID
            interfaceLanguage = persisted.interfaceLanguage
            appTheme = persisted.appTheme
            resultPanelFontSize = persisted.resultPanelFontSize
            modelProfiles = persisted.modelProfiles
            // JSON stores blacklist flags (true = disabled). Only the legacy
            // UserDefaults migration below uses false = disabled.
            appEnabledOverrides = persisted.appEnabledOverrides.filter { $0.value }
            return
        }

        // Do not replace an unreadable existing file with legacy/default settings.
        guard allowLegacyMigration, !FileManager.default.fileExists(atPath: configFileURL.path) else { return }

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
        if defaults.object(forKey: "quickAskEnabled") != nil {
            quickAskEnabled = defaults.bool(forKey: "quickAskEnabled")
        }
        if let value = defaults.string(forKey: "quickAskShortcut"), !value.isEmpty {
            quickAskShortcut = value
        }
        if let value = defaults.string(forKey: "quickAskPrompt"), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            quickAskPrompt = value
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
        if defaults.object(forKey: "resultPanelFontSize") != nil {
            resultPanelFontSize = defaults.double(forKey: "resultPanelFontSize")
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

    private static func sanitizedResultPanelFontSize(_ value: Double) -> Double {
        min(max(value, resultPanelFontSizeRange.lowerBound), resultPanelFontSizeRange.upperBound)
    }
}
