import Foundation

enum StreamChunk {
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

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" {
                            continuation.yield(.done)
                            break
                        }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any] else {
                            continue
                        }

                        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                            continuation.yield(.thinking(reasoning))
                        } else if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
                            continuation.yield(.thinking(reasoning))
                        }

                        if let content = delta["content"] as? String, !content.isEmpty {
                            continuation.yield(.text(content))
                        }
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
        let apiKey = AppSettings.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw LLMError.apiKeyMissing
        }

        let settings = AppSettings.shared
        var baseURL = settings.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseURL.hasSuffix("/") {
            baseURL.removeLast()
        }

        let endpoint: String
        if baseURL.hasSuffix("/v1") {
            endpoint = "\(baseURL)/chat/completions"
        } else if baseURL.contains("/v1/") {
            endpoint = baseURL
        } else {
            endpoint = "\(baseURL)/v1/chat/completions"
        }

        guard let url = URL(string: endpoint) else {
            throw LLMError.serverError("Invalid API URL: \(endpoint)")
        }

        print("[PickLingo] Request to: \(endpoint), model: \(settings.apiModel), stream: \(stream), thinkMode: \(thinkMode)")

        var requestBody: [String: Any] = [
            "model": settings.apiModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
            ],
            "temperature": 0.3,
            "max_tokens": 4096,
        ]

        if stream {
            requestBody["stream"] = true
        }

        // Keep payload compatible with OpenAI-compatible backends that don't accept
        // a `reasoning` object on chat-completions requests.
        requestBody["reasoning"] = ["enabled": thinkMode]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = stream ? 120 : 30
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        return request
    }
}
