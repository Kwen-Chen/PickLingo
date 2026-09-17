import XCTest
@testable import PickLingoCore

final class ChatCompletionTests: XCTestCase {
    private func request(think: Bool = false, stream: Bool = false) throws -> URLRequest {
        try ChatCompletionRequest.make(baseURL: "http://localhost:8080/v1", model: "configured-model", apiKey: "test-key",
                                       systemPrompt: "System", userMessage: "User", stream: stream, thinkMode: think)
    }

    func testStandardRequestDoesNotSendVendorReasoningOrForceTemperature() throws {
        let request = try request()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["model", "messages", "max_completion_tokens", "stream"])
        XCTAssertEqual(json["model"] as? String, "configured-model")
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 4096)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(json["messages"] as? [[String: String]], [["role": "system", "content": "System"], ["role": "user", "content": "User"]])
    }

    func testThinkingUsesReasoningEffortInStreamingAndNonStreamingRequests() throws {
        for streaming in [true, false] {
            let request = try request(think: true, stream: streaming)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(json["reasoning_effort"] as? String, "medium")
            XCTAssertNil(json["reasoning"])
            XCTAssertEqual(json["stream"] as? Bool, streaming)
        }
    }

    func testStandardStreamingTextUsageAndDoneEvents() throws {
        XCTAssertEqual(try ChatCompletionStreamParser.parse(#"{"choices":[{"delta":{"role":"assistant","content":"Hello"}}]}"#), [.text("Hello")])
        XCTAssertEqual(try ChatCompletionStreamParser.parse(#"{"choices":[],"usage":{"total_tokens":4}}"#), [])
        XCTAssertEqual(try ChatCompletionStreamParser.parse("[DONE]"), [.done])
    }

    func testStreamingErrorsAreNotSilentlyIgnored() throws {
        XCTAssertThrowsError(try ChatCompletionStreamParser.parse(#"{"error":{"message":"Invalid model"}}"#)) {
            XCTAssertEqual($0.localizedDescription, "Invalid model")
        }
        XCTAssertThrowsError(try ChatCompletionStreamParser.parse("not json"))
    }
}
