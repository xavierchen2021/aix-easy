import Foundation

struct PluginConfig: Codable {
    let pluginId: String
    var isEnabled: Bool
    var customSettings: [String: String]
    
    init(pluginId: String, isEnabled: Bool = true, customSettings: [String: String] = [:]) {
        self.pluginId = pluginId
        self.isEnabled = isEnabled
        self.customSettings = customSettings
    }
}

@MainActor
class PluginConfigManager {
    static let shared = PluginConfigManager()
    private let configKey = "pluginConfigs"
    private let store: SettingsStore
    
    @Published var pluginConfigs: [String: PluginConfig] = [:]
    
    private init() {
        self.store = AppDatabase.shared.settingsStore
        loadConfigs()
    }
    
    private func loadConfigs() {
        if let jsonString = store.loadConfig(key: configKey),
           let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: PluginConfig].self, from: data) {
            self.pluginConfigs = decoded
        }
    }
    
    private func saveConfigs() {
        if let data = try? JSONEncoder().encode(pluginConfigs),
           let str = String(data: data, encoding: .utf8) {
            try? store.saveConfig(key: configKey, value: str)
        }
    }
    
    func getPluginConfig(pluginId: String) -> PluginConfig {
        return pluginConfigs[pluginId] ?? PluginConfig(pluginId: pluginId)
    }
    
    func updatePluginConfig(_ config: PluginConfig) {
        pluginConfigs[config.pluginId] = config
        saveConfigs()
        NotificationCenter.default.post(name: Notification.Name("pluginConfigChanged"), object: nil)
    }
    
    func setPluginEnabled(pluginId: String, enabled: Bool) {
        var config = getPluginConfig(pluginId: pluginId)
        config.isEnabled = enabled
        updatePluginConfig(config)
    }
    
    func setPluginCustomSetting(pluginId: String, key: String, value: String) {
        var config = getPluginConfig(pluginId: pluginId)
        config.customSettings[key] = value
        updatePluginConfig(config)
    }
    
    func getAllPluginConfigs() -> [PluginConfig] {
        return Array(pluginConfigs.values)
    }
}