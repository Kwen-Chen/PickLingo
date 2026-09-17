import XCTest
@testable import PickLingoCore

final class SettingsTests: XCTestCase {
    @MainActor
    func testBlacklistSurvivesSaveReloadAndRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(configDirectory: directory)
        settings.setAppBlacklisted(true, for: "com.mitchellh.ghostty")
        settings.setAppBlacklisted(true, for: "com.microsoft.VSCode")
        settings.saveImmediately()
        let loaded = AppSettings(configDirectory: directory)
        XCTAssertFalse(loaded.isAppEnabled(bundleID: "com.mitchellh.ghostty"))
        XCTAssertFalse(loaded.isAppEnabled(bundleID: "com.microsoft.VSCode"))
        XCTAssertTrue(loaded.isAppEnabled(bundleID: "com.apple.TextEdit"))
        loaded.setAppBlacklisted(false, for: "com.microsoft.VSCode")
        loaded.saveImmediately()
        let reloaded = AppSettings(configDirectory: directory)
        XCTAssertTrue(reloaded.isAppEnabled(bundleID: "com.microsoft.VSCode"))
        XCTAssertFalse(reloaded.isAppEnabled(bundleID: "com.mitchellh.ghostty"))
    }

    @MainActor
    func testLatestEditsAreFlushedBeforeQuit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(configDirectory: directory)
        settings.apiModel = "first"
        settings.apiModel = "latest"
        settings.isEnabled = false
        settings.saveImmediately()
        let loaded = AppSettings(configDirectory: directory)
        XCTAssertEqual(loaded.apiModel, "latest")
        XCTAssertFalse(loaded.isEnabled)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("config.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
