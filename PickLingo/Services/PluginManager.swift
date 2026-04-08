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
            return decoded.sorted { $0.order < $1.order }
        } catch {
            print("[PickLingo] Failed to load plugins, using defaults: \(error)")
            return Plugin.builtInPlugins
        }
    }

    private func reindex() {
        for i in plugins.indices {
            plugins[i].order = i
        }
    }
}
