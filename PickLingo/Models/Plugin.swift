import Foundation

// MARK: - Action Options

struct ActionOptions: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let copy       = ActionOptions(rawValue: 1 << 0)
    static let insert     = ActionOptions(rawValue: 1 << 1)
    static let replace    = ActionOptions(rawValue: 1 << 2)
    static let regenerate = ActionOptions(rawValue: 1 << 3)
    static let followUp   = ActionOptions(rawValue: 1 << 4)

    static let all: ActionOptions = [.copy, .insert, .replace, .regenerate, .followUp]
    static let copyOnly: ActionOptions = [.copy, .regenerate, .followUp]
    static let allWithoutFollowUp: ActionOptions = [.copy, .insert, .replace, .regenerate]
    static let copyWithRegenerateOnly: ActionOptions = [.copy, .regenerate]
}

// MARK: - Plugin

struct Plugin: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var icon: String              // SF Symbol name
    var prompt: String            // System prompt template. Placeholders: {selected_text}, {source}, {target}, {user_input}
    var isEnabled: Bool
    var order: Int
    var isBuiltIn: Bool           // Built-in plugins cannot be deleted
    var needsUserInput: Bool      // If true, show text field before execution
    var userInputPlaceholder: String?

    /// The stable identifier used to match built-in plugins across resets.
    var builtInID: String?

    /// Which action buttons (Copy / Insert / Replace) to show in the result panel.
    var enabledActions: ActionOptions

    /// Whether to show source/target language selectors in the result panel header.
    var showLanguageControls: Bool

    // MARK: - Backward-compatible decoding

    init(
        id: UUID, name: String, icon: String, prompt: String,
        isEnabled: Bool, order: Int, isBuiltIn: Bool, needsUserInput: Bool,
        userInputPlaceholder: String?, builtInID: String?,
        enabledActions: ActionOptions = .all,
        showLanguageControls: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.order = order
        self.isBuiltIn = isBuiltIn
        self.needsUserInput = needsUserInput
        self.userInputPlaceholder = userInputPlaceholder
        self.builtInID = builtInID
        self.enabledActions = enabledActions
        self.showLanguageControls = showLanguageControls
    }

    // Decode with defaults for older JSON that lacks the new keys
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decode(String.self, forKey: .icon)
        prompt = try c.decode(String.self, forKey: .prompt)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        order = try c.decode(Int.self, forKey: .order)
        isBuiltIn = try c.decode(Bool.self, forKey: .isBuiltIn)
        needsUserInput = try c.decode(Bool.self, forKey: .needsUserInput)
        userInputPlaceholder = try c.decodeIfPresent(String.self, forKey: .userInputPlaceholder)
        builtInID = try c.decodeIfPresent(String.self, forKey: .builtInID)
        enabledActions = try c.decodeIfPresent(ActionOptions.self, forKey: .enabledActions) ?? .all
        showLanguageControls = try c.decodeIfPresent(Bool.self, forKey: .showLanguageControls) ?? false
    }
}

// MARK: - Built-in Plugin Definitions

extension Plugin {
    static let builtInPlugins: [Plugin] = [
        Plugin(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: String(localized: "Translate"),
            icon: "translate",
            prompt: """
            You are a professional translator. Translate the following text from {source} to {target}. \
            Return ONLY the translated text without any explanation, notes, or extra formatting. \
            Preserve the original formatting (line breaks, punctuation style) as closely as possible.

            Text:
            {selected_text}
            """,
            isEnabled: true,
            order: 0,
            isBuiltIn: true,
            needsUserInput: false,
            userInputPlaceholder: nil,
            builtInID: "translate",
            enabledActions: .allWithoutFollowUp,
            showLanguageControls: true
        ),
        Plugin(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: String(localized: "Explain"),
            icon: "book",
            prompt: """
            Explain the following text clearly and concisely. Break down any complex concepts, \
            technical terms, or jargon into simple language. Provide context where helpful.

            Text:
            {selected_text}
            """,
            isEnabled: true,
            order: 1,
            isBuiltIn: true,
            needsUserInput: false,
            userInputPlaceholder: nil,
            builtInID: "explain",
            enabledActions: .copyOnly,
            showLanguageControls: false
        ),
        Plugin(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: String(localized: "Polish"),
            icon: "wand.and.stars",
            prompt: """
            Improve and polish the following text. Fix grammar, spelling, and punctuation errors. \
            Enhance clarity and readability while preserving the original meaning and tone. \
            Return ONLY the improved text without explanations.

            Text:
            {selected_text}
            """,
            isEnabled: true,
            order: 2,
            isBuiltIn: true,
            needsUserInput: false,
            userInputPlaceholder: nil,
            builtInID: "polish",
            enabledActions: .allWithoutFollowUp,
            showLanguageControls: false
        ),
        Plugin(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: String(localized: "Summarize"),
            icon: "text.quote",
            prompt: """
            Summarize the following text concisely. Capture the key points and main ideas \
            in a brief paragraph. Keep it clear and informative.

            Text:
            {selected_text}
            """,
            isEnabled: true,
            order: 3,
            isBuiltIn: true,
            needsUserInput: false,
            userInputPlaceholder: nil,
            builtInID: "summarize",
            enabledActions: .copyWithRegenerateOnly,
            showLanguageControls: false
        ),
        Plugin(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: String(localized: "Ask"),
            icon: "bubble.left.and.text.bubble.right",
            prompt: """
            Based on the following text, answer the user's question thoughtfully and accurately.

            Text:
            {selected_text}

            Question:
            {user_input}
            """,
            isEnabled: true,
            order: 4,
            isBuiltIn: true,
            needsUserInput: true,
            userInputPlaceholder: String(localized: "Ask a question about this text..."),
            builtInID: "ask",
            enabledActions: .copyOnly,
            showLanguageControls: false
        ),
    ]

    /// Returns the default version of a built-in plugin by its builtInID.
    static func defaultBuiltIn(id: String) -> Plugin? {
        builtInPlugins.first { $0.builtInID == id }
    }

    /// Whether this is the Translate plugin (needs special language handling).
    var isTranslatePlugin: Bool {
        builtInID == "translate"
    }

    var uiDisplayName: String {
        guard isBuiltIn, let builtInID else { return name }
        let defaults = Self.defaultNames(for: builtInID)
        guard let englishDefault = defaults.first else { return name }
        if defaults.contains(name) {
            return UIString(englishDefault)
        }
        return name
    }

    private static func defaultNames(for builtInID: String) -> [String] {
        switch builtInID {
        case "translate": return ["Translate", "翻译"]
        case "explain": return ["Explain", "解释"]
        case "polish": return ["Polish", "润色"]
        case "summarize": return ["Summarize", "总结"]
        case "ask": return ["Ask", "提问"]
        default: return []
        }
    }
}
