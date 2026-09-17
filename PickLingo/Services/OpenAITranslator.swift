import Foundation

enum StreamChunk: Equatable {
    case text(String)
    case thinking(String)
    case done
}

enum LLMError: LocalizedError {
    case apiKeyMissing
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return String(localized: "API key is not configured. Please set it in Settings.")
        case .networkError(let error):
            return String(localized: "Network error: \(error.localizedDescription)")
        case .invalidResponse:
            return String(localized: "Invalid response from AI service.")
        case .rateLimited:
            return String(localized: "Rate limited. Please try again later.")
        case .serverError(let message):
            return message
        }
    }
}

@MainActor
final class OpenAIService {

    // MARK: - Non-streaming

    func execute(systemPrompt: String, userMessage: String, thinkMode: Bool = false) async throws -> String {
        let request = try buildRequest(systemPrompt: systemPrompt, userMessage: userMessage, stream: false, thinkMode: thinkMode)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""

        if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw LLMError.serverError("[\(httpResponse.statusCode)] \(message)")
            }
            throw LLMError.serverError("[\(httpResponse.statusCode)] \(responseBody.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Streaming

    func executeStream(systemPrompt: String, userMessage: String, thinkMode: Bool = false) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(systemPrompt: systemPrompt, userMessage: userMessage, stream: true, thinkMode: thinkMode)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode == 429 {
                        continuation.finish(throwing: LLMError.rateLimited)
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                            if errorData.count >= 65_536 { break }
                        }
                        let errorBody = String(data: errorData, encoding: .utf8) ?? ""
                        if let json = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                           let error = json["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            continuation.finish(throwing: LLMError.serverError("[\(httpResponse.statusCode)] \(message)"))
                        } else {
                            continuation.finish(throwing: LLMError.serverError("[\(httpResponse.statusCode)] \(errorBody.prefix(200))"))
                        }
                        return
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)

                        let chunks = try ChatCompletionStreamParser.parse(payload)
                        for chunk in chunks { continuation.yield(chunk) }
                        if chunks.contains(.done) { break }
                    }

                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request Builder

    private func buildRequest(systemPrompt: String, userMessage: String, stream: Bool, thinkMode: Bool) throws -> URLRequest {
        let settings = AppSettings.shared
        return try ChatCompletionRequest.make(
            baseURL: settings.apiBaseURL, model: settings.apiModel, apiKey: settings.apiKey,
            systemPrompt: systemPrompt, userMessage: userMessage,
            stream: stream, thinkMode: thinkMode
        )
    }

}

/// Preserve provider-specific path prefixes and query parameters. HTTP is supported
/// for explicitly configured local/internal endpoints; HTTPS keeps standard TLS validation.
enum APIEndpoint {
    static func resolve(_ input: String) throws -> URL {
        guard var components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              components.user == nil, components.password == nil, components.fragment == nil else {
            throw LLMError.serverError(UIString("Enter a valid HTTP or HTTPS API base URL."))
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") {
            path += path.hasSuffix("/v1") ? "/chat/completions" : "/v1/chat/completions"
        }
        components.path = path
        guard let url = components.url else { throw LLMError.invalidResponse }
        return url
    }
}

/// Standard OpenAI Chat Completions fields only. Do not force sampling controls
/// or vendor-specific reasoning objects on models that do not support them.
enum ChatCompletionRequest {
    static func make(
        baseURL: String, model: String, apiKey: String,
        systemPrompt: String, userMessage: String, stream: Bool, thinkMode: Bool
    ) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LLMError.apiKeyMissing }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw LLMError.serverError(UIString("Enter an API model name.")) }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_completion_tokens": 4096,
            "stream": stream
        ]
        if thinkMode { body["reasoning_effort"] = "medium" }
        var request = URLRequest(url: try APIEndpoint.resolve(baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = stream ? 120 : 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

enum ChatCompletionStreamParser {
    static func parse(_ payload: String) throws -> [StreamChunk] {
        if payload == "[DONE]" { return [.done] }
        guard let data = payload.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw LLMError.serverError(message)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else { return [] }
        var chunks: [StreamChunk] = []
        // Accept optional gateway response extensions without sending nonstandard fields.
        if let reasoning = (delta["reasoning_content"] ?? delta["reasoning"]) as? String, !reasoning.isEmpty {
            chunks.append(.thinking(reasoning))
        }
        if let content = delta["content"] as? String, !content.isEmpty { chunks.append(.text(content)) }
        return chunks
    }
}
