import XCTest
@testable import PickLingoCore

final class SettingsTests: XCTestCase {
    @MainActor
    func testToolbarAppearanceSurvivesRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(configDirectory: directory)
        settings.tooltipStyle = .labeled
        settings.tooltipPluginSpacing = 18
        settings.tooltipHorizontalOffset = -45
        settings.tooltipVerticalGap = 36
        settings.tooltipPosition = .above
        settings.saveImmediately()
        let loaded = AppSettings(configDirectory: directory)
        XCTAssertEqual(loaded.tooltipStyle, .labeled)
        XCTAssertEqual(loaded.tooltipPluginSpacing, 18)
        XCTAssertEqual(loaded.tooltipHorizontalOffset, -45)
        XCTAssertEqual(loaded.tooltipVerticalGap, 36)
        XCTAssertEqual(loaded.tooltipPosition, .above)
    }

    @MainActor
    func testOlderSettingsKeepAPIConfigurationAndDefaultToolbar() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(configDirectory: directory)
        settings.apiModel = "custom-model"
        settings.apiKey = "test-fixture-key"
        settings.saveImmediately()
        let file = directory.appendingPathComponent("config.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json.removeValue(forKey: "tooltipStyle")
        json.removeValue(forKey: "tooltipPluginSpacing")
        json.removeValue(forKey: "tooltipHorizontalOffset")
        json.removeValue(forKey: "tooltipVerticalGap")
        json.removeValue(forKey: "tooltipPosition")
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let loaded = AppSettings(configDirectory: directory)
        XCTAssertEqual(loaded.apiModel, "custom-model")
        XCTAssertEqual(loaded.apiKey, "test-fixture-key")
        XCTAssertEqual(loaded.tooltipStyle, .floating)
        XCTAssertEqual(loaded.tooltipPluginSpacing, 2)
        XCTAssertEqual(loaded.tooltipHorizontalOffset, 0)
        XCTAssertEqual(loaded.tooltipVerticalGap, 12)
        XCTAssertEqual(loaded.tooltipPosition, .below)

        json["tooltipStyle"] = "a-future-style"
        json["tooltipPluginSpacing"] = 2000
        json["tooltipHorizontalOffset"] = -2000
        json["tooltipVerticalGap"] = -2000
        json["tooltipPosition"] = "unknown-position"
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let future = AppSettings(configDirectory: directory)
        XCTAssertEqual(future.apiKey, "test-fixture-key")
        XCTAssertEqual(future.tooltipStyle, .floating)
        XCTAssertEqual(future.tooltipPluginSpacing, 24)
        XCTAssertEqual(future.tooltipHorizontalOffset, -120)
        XCTAssertEqual(future.tooltipVerticalGap, 0)
        XCTAssertEqual(future.tooltipPosition, .below)
        future.tooltipVerticalGap = .nan
        future.tooltipHorizontalOffset = .infinity
        XCTAssertEqual(future.tooltipVerticalGap, 12)
        XCTAssertEqual(future.tooltipHorizontalOffset, 0)
        future.tooltipPluginSpacing = -.infinity
        XCTAssertEqual(future.tooltipPluginSpacing, 2)
        future.tooltipPluginSpacing = -20
        XCTAssertEqual(future.tooltipPluginSpacing, 0)
    }

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
