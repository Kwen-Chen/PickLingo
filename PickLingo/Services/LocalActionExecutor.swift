import Foundation

enum LocalActionExecutionError: LocalizedError {
    case timedOut
    case missingCommand
    case processLaunchFailed(String)
    case commandFailed(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The local action exceeded its 60 second time limit."
        case .missingCommand:
            return "This local action plugin has no command template."
        case .processLaunchFailed(let message):
            return "Failed to run command: \(message)"
        case .commandFailed(let status, let message):
            if message.isEmpty {
                return "Command failed with exit code \(status)."
            }
            return "Command failed with exit code \(status):\n\(message)"
        }
    }
}

final class LocalActionExecutor {
    static let shared = LocalActionExecutor()

    private init() {}

    func execute(
        plugin: Plugin,
        selectedText: String,
        userInput: String? = nil,
        source: String? = nil,
        target: String? = nil
    ) async throws -> String {
        let template = resolveCommandTemplate(for: plugin)
        guard !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalActionExecutionError.missingCommand
        }

        let resolvedCommand = interpolate(
            template: template,
            selectedText: selectedText,
            userInput: userInput ?? "",
            source: source ?? "",
            target: target ?? ""
        )

        let result = try await run(command: resolvedCommand)
        if result.status != 0 {
            let combined = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw LocalActionExecutionError.commandFailed(status: result.status, message: combined)
        }

        var lines: [String] = []
        lines.append("Executed command:")
        lines.append(resolvedCommand)

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty {
            lines.append("")
            lines.append("Output:")
            lines.append(output)
        }

        return lines.joined(separator: "\n")
    }

    private func resolveCommandTemplate(for plugin: Plugin) -> String {
        if let command = plugin.localCommandTemplate,
           !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return command
        }

        // Backward compatibility for old plugins that only had `localAction`.
        switch plugin.localAction {
        case .openURLOrPathInDefaultApp, .openURLInDefaultBrowser, .openPathInDefaultApp:
            return "open {selected_text}"
        case .revealPathInFinder:
            return "open -R {selected_text}"
        case .none:
            return ""
        }
    }

    private func interpolate(
        template: String,
        selectedText: String,
        userInput: String,
        source: String,
        target: String
    ) -> String {
        let values = [
            "{selected_text}": selectedText, "{user_input}": userInput,
            "{source}": source, "{target}": target
        ]
        let pattern = #"\{(?:selected_text|user_input|source|target)\}"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let original = template as NSString
        var command = template
        for match in expression.matches(in: template, range: NSRange(location: 0, length: original.length)).reversed() {
            guard let range = Range(match.range, in: command),
                  let value = values[original.substring(with: match.range)] else { continue }
            let escaped = "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
            command.replaceSubrange(range, with: escaped)
        }
        return command
    }

    private func run(command: String) async throws -> (status: Int32, stdout: String, stderr: String) {
        let execution = LocalCommandExecution()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await execution.run(command: command)
        } onCancel: {
            execution.cancel()
        }
    }
}

/// Temporary output files avoid pipe-buffer deadlocks and inherited pipe descriptors
/// from commands that launch GUI apps. Only a bounded prefix is loaded into memory.
final class LocalCommandExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var canceled = false
    private var timedOut = false
    private let timeoutInterval: TimeInterval

    init(timeout: TimeInterval = 60) { timeoutInterval = timeout }

    func cancel(timedOut: Bool = false) {
        lock.lock()
        canceled = true
        self.timedOut = self.timedOut || timedOut
        let running = process.isRunning
        lock.unlock()
        if running {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    func run(command: String) async throws -> (status: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                          attributes: [.posixPermissions: 0o700])
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let outputURL = directory.appendingPathComponent("stdout")
                    let errorURL = directory.appendingPathComponent("stderr")
                    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
                    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
                    let output = try FileHandle(forWritingTo: outputURL)
                    let errors = try FileHandle(forWritingTo: errorURL)
                    defer { try? output.close(); try? errors.close() }
                    self.process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    self.process.arguments = ["-lc", command]
                    self.process.standardOutput = output
                    self.process.standardError = errors
                    self.process.standardInput = FileHandle.nullDevice
                    self.lock.lock()
                    if self.canceled {
                        self.lock.unlock()
                        throw CancellationError()
                    }
                    do { try self.process.run() }
                    catch { self.lock.unlock(); throw error }
                    self.lock.unlock()

                    // Waiting here never occupies the UI actor. Canceled processes are
                    // terminated; long-running commands get a 60 second execution limit.
                    let timeout = DispatchWorkItem { self.cancel(timedOut: true) }
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.timeoutInterval, execute: timeout)
                    self.process.waitUntilExit()
                    timeout.cancel()
                    self.lock.lock()
                    let canceled = self.canceled
                    let timedOut = self.timedOut
                    self.lock.unlock()
                    if timedOut { throw LocalActionExecutionError.timedOut }
                    if canceled { throw CancellationError() }
                    func read(_ url: URL) throws -> String {
                        let file = try FileHandle(forReadingFrom: url)
                        defer { try? file.close() }
                        let data = try file.read(upToCount: 1_048_576) ?? Data()
                        return String(decoding: data, as: UTF8.self)
                    }
                    continuation.resume(returning: (self.process.terminationStatus, try read(outputURL), try read(errorURL)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
