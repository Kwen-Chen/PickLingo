import Foundation

enum KeychainHelper {
    private static var configDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".picklingo", isDirectory: true)
    }

    private static var secretsFileURL: URL {
        configDirectoryURL.appendingPathComponent("secrets.json")
    }

    private static func loadSecrets() -> [String: String] {
        guard let data = try? Data(contentsOf: secretsFileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveSecrets(_ secrets: [String: String]) {
        do {
            try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(secrets)
            try data.write(to: secretsFileURL, options: .atomic)
        } catch {
            print("[PickLingo] Failed to persist secrets: \(error)")
        }
    }

    static func save(key: String, value: String) {
        var secrets = loadSecrets()
        secrets[key] = value
        saveSecrets(secrets)
    }

    static func load(key: String) -> String? {
        loadSecrets()[key]
    }

    static func delete(key: String) {
        var secrets = loadSecrets()
        secrets.removeValue(forKey: key)
        saveSecrets(secrets)
    }
}
