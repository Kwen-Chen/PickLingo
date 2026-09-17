import XCTest
@testable import PickLingoCore

private func makePlugin(command: String? = nil) -> Plugin {
    Plugin(id: UUID(), name: "Test", icon: "text.bubble", prompt: "test",
           isEnabled: true, order: 0, isBuiltIn: false, needsUserInput: false,
           userInputPlaceholder: nil, builtInID: nil,
           executionMode: command == nil ? .ai : .localAction, localCommandTemplate: command)
}

@MainActor
private final class ControlledExecutor: PluginExecuting {
    var replies: [CheckedContinuation<String, Error>] = []
    var streams: [AsyncThrowingStream<StreamChunk, Error>.Continuation] = []

    func executeStream(text: String, plugin: Plugin, userInput: String?, source: Language?, target: Language?, thinkModeOverride: Bool?) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { streams.append($0) }
    }

    func execute(text: String, plugin: Plugin, userInput: String?, source: Language?, target: Language?, thinkModeOverride: Bool?) async throws -> String {
        // Deliberately ignores cancellation, like an already-completed network reply.
        try await withCheckedThrowingContinuation { replies.append($0) }
    }
}

final class ExecutionTests: XCTestCase {
    @MainActor
    func testOldReplyCannotFinishNewRequestOrOverwriteItsResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(configDirectory: directory)
        settings.streamingEnabled = false
        settings.saveImmediately()
        let executor = ControlledExecutor()
        let model = ResultViewModel(executor: executor, settings: settings)
        model.execute(text: "first", plugin: makePlugin())
        while executor.replies.count < 1 { await Task.yield() }
        model.execute(text: "second", plugin: makePlugin())
        while executor.replies.count < 2 { await Task.yield() }
        executor.replies[0].resume(returning: "stale")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.isGenerating)
        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.resultText, "")
        executor.replies[1].resume(returning: "current")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.resultText, "current")
    }

    @MainActor
    func testStoppedStreamCannotPublishLateChunksIntoRegeneration() async throws {
        let settings = AppSettings(configDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let executor = ControlledExecutor()
        let model = ResultViewModel(executor: executor, settings: settings)
        model.execute(text: "first", plugin: makePlugin())
        while executor.streams.count < 1 { await Task.yield() }
        executor.streams[0].yield(.text("partial"))
        try await Task.sleep(for: .milliseconds(20))
        model.cancelStream()
        XCTAssertFalse(model.isGenerating)
        model.execute(text: "second", plugin: makePlugin())
        while executor.streams.count < 2 { await Task.yield() }
        executor.streams[0].yield(.text(" stale"))
        executor.streams[0].finish()
        executor.streams[1].yield(.thinking("reasoning"))
        executor.streams[1].yield(.text("current"))
        executor.streams[1].finish()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.resultText, "current")
        XCTAssertEqual(model.thinkingText, "reasoning")
        XCTAssertFalse(model.isThinking)
        XCTAssertFalse(model.isGenerating)
    }

    func testLocalCommandCanProduceMoreThanPipeBufferOnBothStreams() async throws {
        let result = try await LocalCommandExecution(timeout: 5).run(command: "for i in {1..10000}; do printf '1234567890'; printf 'abcdefghij' >&2; done")
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.utf8.count, 100_000)
        XCTAssertEqual(result.stderr.utf8.count, 100_000)
    }

    func testLocalPlaceholderValuesRemainLiteralAndPreserveWhitespace() async throws {
        let payload = "  {user_input} ' $(printf unsafe)\n  "
        let result = try await LocalActionExecutor.shared.execute(
            plugin: makePlugin(command: "printf '%s' {selected_text} | /usr/bin/base64"),
            selectedText: payload, userInput: "must not replace the literal token"
        )
        XCTAssertTrue(result.contains(Data(payload.utf8).base64EncodedString()))
    }

    func testLocalCommandTimeoutAlsoStopsCommandsIgnoringSIGTERM() async throws {
        let start = Date()
        do {
            _ = try await LocalCommandExecution(timeout: 0.1).run(command: "trap '' TERM; while true; do :; done")
            XCTFail("Expected timeout")
        } catch LocalActionExecutionError.timedOut {
            XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        }
    }

    func testCancelLocalCommand() async throws {
        let execution = LocalCommandExecution(timeout: 5)
        let task = Task {
            try await withTaskCancellationHandler {
                try await execution.run(command: "while true; do :; done")
            } onCancel: { execution.cancel() }
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }
}
