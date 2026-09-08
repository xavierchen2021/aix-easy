import Foundation
import Combine

@MainActor
class PluginManager: ObservableObject {
    static let shared = PluginManager()
    
    @Published var registeredPlugins: [String: PluginAction] = [:]
    
    private let configManager = PluginConfigManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupConfigObserver()
    }
    
    private func setupConfigObserver() {
        configManager.$pluginConfigs
            .sink { [weak self] _ in
                self?.syncPluginStates()
            }
            .store(in: &cancellables)
    }
    
    private func syncPluginStates() {
        for (pluginId, plugin) in registeredPlugins {
            let config = configManager.getPluginConfig(pluginId: pluginId)
            plugin.isEnabled = config.isEnabled
        }
    }
    
    func register(_ plugin: PluginAction) {
        registeredPlugins[plugin.pluginId] = plugin
        
        let config = configManager.getPluginConfig(pluginId: plugin.pluginId)
        plugin.isEnabled = config.isEnabled
        
        Logger.shared.log("🔌 插件已注册: \(plugin.pluginId) - \(plugin.displayName)")
    }
    
    func unregister(pluginId: String) {
        registeredPlugins.removeValue(forKey: pluginId)
        Logger.shared.log("🔌 插件已注销: \(pluginId)")
    }
    
    func enable(pluginId: String) {
        guard registeredPlugins[pluginId] != nil else {
            Logger.shared.log("⚠️ 无法启用不存在的插件: \(pluginId)")
            return
        }
        configManager.setPluginEnabled(pluginId: pluginId, enabled: true)
        registeredPlugins[pluginId]?.isEnabled = true
        Logger.shared.log("✅ 插件已启用: \(pluginId)")
    }
    
    func disable(pluginId: String) {
        configManager.setPluginEnabled(pluginId: pluginId, enabled: false)
        registeredPlugins[pluginId]?.isEnabled = false
        Logger.shared.log("❌ 插件已禁用: \(pluginId)")
    }
    
    func execute(pluginId: String, context: PluginContext) throws {
        guard let plugin = registeredPlugins[pluginId] else {
            throw PluginError.pluginNotFound(pluginId)
        }
        
        guard plugin.isEnabled else {
            throw PluginError.pluginDisabled(pluginId)
        }
        
        Logger.shared.log("🚀 执行插件: \(pluginId)")
        try plugin.execute(context: context)
    }
    
    func getPlugin(withId id: String) -> PluginAction? {
        return registeredPlugins[id]
    }
    
    func getAllPlugins() -> [PluginAction] {
        return Array(registeredPlugins.values).sorted { $0.displayName < $1.displayName }
    }
    
    func getEnabledPlugins() -> [PluginAction] {
        return registeredPlugins.values.filter { $0.isEnabled }.sorted { $0.displayName < $1.displayName }
    }
}
