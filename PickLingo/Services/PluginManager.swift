import Foundation
import Combine

final class PluginManager: ObservableObject {
    static let shared = PluginManager()

    @Published var plugins: [Plugin] = []

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private static let saveDebounceInterval: TimeInterval = 0.5

    // Cache for enabledPlugins — invalidated when plugins change
    private var _enabledPluginsCache: [Plugin]?

    private init() {
        // ~/.picklingo/plugins.json
        let appDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".picklingo", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        fileURL = appDir.appendingPathComponent("plugins.json")
        plugins = loadPlugins()
    }

    // MARK: - Public API

    /// Returns enabled plugins sorted by order. Result is cached.
    func enabledPlugins() -> [Plugin] {
        if let cached = _enabledPluginsCache { return cached }
        let result = plugins.filter(\.isEnabled).sorted { $0.order < $1.order }
        _enabledPluginsCache = result
        return result
    }

    func save() {
        invalidateCache()

        // Debounce: coalesce rapid saves (e.g. during typing in prompt editor)
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSave()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounceInterval, execute: workItem)
    }

    /// Force immediate save (for critical operations like delete, reorder).
    func saveImmediately() {
        invalidateCache()
        saveWorkItem?.cancel()
        performSave()
    }

    func addPlugin(_ plugin: Plugin) {
        var newPlugin = plugin
        newPlugin.order = (plugins.map(\.order).max() ?? -1) + 1
        plugins.append(newPlugin)
        saveImmediately()
    }

    func deletePlugin(_ plugin: Plugin) {
        guard !plugin.isBuiltIn else { return }
        plugins.removeAll { $0.id == plugin.id }
        reindex()
        saveImmediately()
    }

    func updatePlugin(_ plugin: Plugin) {
        guard let index = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        plugins[index] = plugin
        save()
    }

    func movePlugin(fromOffsets: IndexSet, toOffset: Int) {
        plugins.move(fromOffsets: fromOffsets, toOffset: toOffset)
        reindex()
        saveImmediately()
    }

    func resetToDefaults() {
        plugins = Plugin.builtInPlugins
        saveImmediately()
    }

    func resetBuiltInPlugin(_ plugin: Plugin) {
        guard let builtInID = plugin.builtInID,
              let defaultPlugin = Plugin.defaultBuiltIn(id: builtInID),
              let index = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        var restored = defaultPlugin
        restored.id = plugin.id
        restored.order = plugin.order
        restored.isEnabled = plugin.isEnabled
        plugins[index] = restored
        saveImmediately()
    }

    // MARK: - Private

    private func invalidateCache() {
        _enabledPluginsCache = nil
    }

    private func performSave() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(plugins)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[PickLingo] Failed to save plugins: \(error)")
        }
    }

    private func loadPlugins() -> [Plugin] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = Plugin.builtInPlugins
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(defaults) {
                try? data.write(to: fileURL, options: .atomic)
            }
            return defaults
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Plugin].self, from: data)
            let sorted = decoded.sorted { $0.order < $1.order }
            let normalizedBuiltIns = normalizeLegacyBuiltIns(in: sorted)
            let normalized = normalizeLegacyLocalActionCommands(in: normalizedBuiltIns)
            let merged = mergeMissingBuiltIns(into: normalized)
            if merged != sorted {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(merged) {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
            return merged
        } catch {
            print("[PickLingo] Failed to load plugins, using defaults: \(error)")
            return Plugin.builtInPlugins
        }
    }

    private func normalizeLegacyBuiltIns(in plugins: [Plugin]) -> [Plugin] {
        let openResourceID = "open-resource"
        let legacyOpenIDs: Set<String> = ["open-link", "open-path"]

        var result = plugins
        let hasOpenResource = result.contains { $0.builtInID == openResourceID }
        let legacyIndices = result.indices.filter { index in
            if let id = result[index].builtInID {
                return legacyOpenIDs.contains(id)
            }
            return false
        }

        guard !legacyIndices.isEmpty else { return result }

        if hasOpenResource {
            result.removeAll { plugin in
                if let builtInID = plugin.builtInID {
                    return legacyOpenIDs.contains(builtInID)
                }
                return false
            }
            return result.sorted { $0.order < $1.order }
        }

        let legacyPlugins = legacyIndices.map { result[$0] }
        let primary = legacyPlugins.first { $0.builtInID == "open-link" } ?? legacyPlugins[0]
        guard let defaultOpenResource = Plugin.defaultBuiltIn(id: openResourceID) else {
            return result
        }

        let minOrder = legacyPlugins.map(\.order).min() ?? primary.order
        let mergedEnabled = legacyPlugins.contains { $0.isEnabled }

        var transformed = defaultOpenResource
        transformed.id = primary.id
        transformed.order = minOrder
        transformed.isEnabled = mergedEnabled
        transformed.name = primary.name
        transformed.icon = primary.icon
        transformed.executionMode = .localAction
        transformed.localCommandTemplate = "open {selected_text}"
        transformed.localAction = .openURLOrPathInDefaultApp

        result.removeAll { plugin in
            if let builtInID = plugin.builtInID {
                return legacyOpenIDs.contains(builtInID)
            }
            return false
        }
        result.append(transformed)
        return result.sorted { $0.order < $1.order }
    }

    private func normalizeLegacyLocalActionCommands(in plugins: [Plugin]) -> [Plugin] {
        var normalized = plugins
        var changed = false

        for index in normalized.indices {
            guard normalized[index].executionMode == .localAction else { continue }
            let current = normalized[index].localCommandTemplate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !current.isEmpty { continue }

            normalized[index].localCommandTemplate = legacyCommandTemplate(for: normalized[index].localAction)
            changed = true
        }

        return changed ? normalized : plugins
    }

    private func legacyCommandTemplate(for action: LocalActionType?) -> String {
        switch action {
        case .revealPathInFinder:
            return "open -R {selected_text}"
        case .openURLOrPathInDefaultApp, .openURLInDefaultBrowser, .openPathInDefaultApp, .none:
            return "open {selected_text}"
        }
    }

    private func mergeMissingBuiltIns(into plugins: [Plugin]) -> [Plugin] {
        var merged = plugins
        let existingBuiltInIDs = Set(plugins.compactMap(\.builtInID))
        var nextOrder = (plugins.map(\.order).max() ?? -1) + 1

        for builtIn in Plugin.builtInPlugins {
            guard let builtInID = builtIn.builtInID else { continue }
            if existingBuiltInIDs.contains(builtInID) { continue }
            var appended = builtIn
            appended.order = nextOrder
            nextOrder += 1
            merged.append(appended)
        }

        return merged.sorted { $0.order < $1.order }
    }

    private func reindex() {
        for i in plugins.indices {
            plugins[i].order = i
        }
    }
}
