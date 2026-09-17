import Foundation

@MainActor
protocol PluginExecuting {
    func executeStream(text: String, plugin: Plugin, userInput: String?, source: Language?, target: Language?, thinkModeOverride: Bool?) -> AsyncThrowingStream<StreamChunk, Error>
    func execute(text: String, plugin: Plugin, userInput: String?, source: Language?, target: Language?, thinkModeOverride: Bool?) async throws -> String
}

/// Executes plugins by building prompts from plugin templates and calling the OpenAI-compatible API.
@MainActor
final class PluginExecutor: PluginExecuting {
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
        if plugin.isLocalActionPlugin {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let message = try await LocalActionExecutor.shared.execute(
                            plugin: plugin,
                            selectedText: text,
                            userInput: userInput,
                            source: source?.nativeName,
                            target: target?.nativeName
                        )
                        continuation.yield(.text(message))
                        continuation.yield(.done)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

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
        if plugin.isLocalActionPlugin {
            return try await LocalActionExecutor.shared.execute(
                plugin: plugin,
                selectedText: text,
                userInput: userInput,
                source: source?.nativeName,
                target: target?.nativeName
            )
        }

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
        // Always deliver the selected text in the user message, even when the
        // plugin template also embeds {selected_text} in the system prompt.
        // Burying the content only in the system role causes many
        // OpenAI-compatible models (especially smaller/local ones) to
        // under-weight or ignore it — the panel shows the word, but the model
        // acts on the near-empty user turn. Putting the content in the user
        // message is what these models reliably attend to.
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = userInput?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let question, !question.isEmpty {
            if text.isEmpty { return question }
            return "\(text)\n\n\(question)"
        }

        // No user input (e.g. Translate/Explain/Polish/Summarize): send the
        // selected text itself. Fall back to a nudge only when nothing is
        // selected (e.g. Quick Ask with an empty selection).
        return text.isEmpty ? "Please proceed." : text
    }

    // MARK: - Private

    private func getOpenAIService() -> OpenAIService {
        if let existing = openAIService { return existing }
        let service = OpenAIService()
        openAIService = service
        return service
    }
}
