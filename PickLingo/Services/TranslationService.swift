import Foundation

/// Executes plugins by building prompts from plugin templates and calling the OpenAI-compatible API.
final class PluginExecutor {
    static let shared = PluginExecutor()

    private var openAIService: OpenAIService?

    private init() {}

    // MARK: - Streaming Execution

    func executeStream(
        text: String,
        plugin: Plugin,
        userInput: String? = nil,
        source: Language? = nil,
        target: Language? = nil,
        thinkModeOverride: Bool? = nil
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let settings = AppSettings.shared
        let detectedSource: Language = {
            if let source { return source }
            if settings.autoDetectLanguage {
                return LanguageDetector.detect(text) ?? .english
            }
            return .english
        }()
        let resolvedTarget = target ?? LanguageDetector.targetLanguage(for: detectedSource)

        let systemPrompt = buildSystemPrompt(
            plugin: plugin,
            selectedText: text,
            userInput: userInput,
            source: detectedSource,
            target: resolvedTarget
        )

        let userMessage = buildUserMessage(
            plugin: plugin,
            selectedText: text,
            userInput: userInput
        )

        let service = getOpenAIService()
        let resolvedThinkMode = thinkModeOverride ?? settings.thinkModeEnabled
        return service.executeStream(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            thinkMode: resolvedThinkMode
        )
    }

    // MARK: - Non-streaming Execution

    func execute(
        text: String,
        plugin: Plugin,
        userInput: String? = nil,
        source: Language? = nil,
        target: Language? = nil,
        thinkModeOverride: Bool? = nil
    ) async throws -> String {
        let settings = AppSettings.shared
        let detectedSource: Language = {
            if let source { return source }
            if settings.autoDetectLanguage {
                return LanguageDetector.detect(text) ?? .english
            }
            return .english
        }()
        let resolvedTarget = target ?? LanguageDetector.targetLanguage(for: detectedSource)

        let systemPrompt = buildSystemPrompt(
            plugin: plugin,
            selectedText: text,
            userInput: userInput,
            source: detectedSource,
            target: resolvedTarget
        )

        let userMessage = buildUserMessage(
            plugin: plugin,
            selectedText: text,
            userInput: userInput
        )

        let service = getOpenAIService()
        let resolvedThinkMode = thinkModeOverride ?? settings.thinkModeEnabled
        return try await service.execute(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            thinkMode: resolvedThinkMode
        )
    }

    /// Call this when API settings change.
    func refreshService() {
        openAIService = nil
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(
        plugin: Plugin,
        selectedText: String,
        userInput: String?,
        source: Language,
        target: Language
    ) -> String {
        var prompt = plugin.prompt
        prompt = prompt.replacingOccurrences(of: "{source}", with: source.nativeName)
        prompt = prompt.replacingOccurrences(of: "{target}", with: target.nativeName)
        prompt = prompt.replacingOccurrences(of: "{selected_text}", with: selectedText)
        prompt = prompt.replacingOccurrences(of: "{user_input}", with: userInput ?? "")
        return prompt
    }

    private func buildUserMessage(
        plugin: Plugin,
        selectedText: String,
        userInput: String?
    ) -> String {
        // If the prompt already contains {selected_text}, the text is embedded in the system prompt.
        // In that case, send a minimal user message.
        let promptContainsSelectedText = plugin.prompt.contains("{selected_text}")

        if promptContainsSelectedText {
            // The selected text is already in the system prompt.
            // If there's user input not already embedded, add it.
            if let input = userInput, !input.isEmpty, !plugin.prompt.contains("{user_input}") {
                return input
            }
            return "Please proceed."
        } else {
            // Selected text goes as the user message
            if let input = userInput, !input.isEmpty {
                return "\(selectedText)\n\n\(input)"
            }
            return selectedText
        }
    }

    // MARK: - Private

    private func getOpenAIService() -> OpenAIService {
        if let existing = openAIService { return existing }
        let service = OpenAIService()
        openAIService = service
        return service
    }
}
