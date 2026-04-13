import Foundation

enum LocalActionExecutionError: LocalizedError {
    case missingCommand
    case processLaunchFailed(String)
    case commandFailed(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
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
    ) throws -> String {
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

        let result = try run(command: resolvedCommand)
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
        var command = template
        command = command.replacingOccurrences(of: "{selected_text}", with: shellEscape(selectedText))
        command = command.replacingOccurrences(of: "{user_input}", with: shellEscape(userInput))
        command = command.replacingOccurrences(of: "{source}", with: shellEscape(source))
        command = command.replacingOccurrences(of: "{target}", with: shellEscape(target))
        return command
    }

    private func shellEscape(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(safe)'"
    }

    private func run(command: String) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw LocalActionExecutionError.processLaunchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(decoding: outData, as: UTF8.self)
        let stderr = String(decoding: errData, as: UTF8.self)
        return (process.terminationStatus, stdout, stderr)
    }
}
