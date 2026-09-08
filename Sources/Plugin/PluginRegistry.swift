import Foundation

@MainActor
class PluginRegistry {
    static let shared = PluginRegistry()
    
    private init() {}
    
    func registerBuiltinPlugins() {
        registerCommonDocumentPlugins()
        registerUtilityPlugins()
        registerWindowManagementPlugins()
        
        Logger.shared.log("📦 已注册所有内置插件")
    }
    
    private func registerCommonDocumentPlugins() {
        let openDocumentPlugin = OpenDocumentPlugin()
        PluginManager.shared.register(openDocumentPlugin)
        
        let searchDocumentPlugin = SearchDocumentPlugin()
        PluginManager.shared.register(searchDocumentPlugin)
        
        let recentDocumentsPlugin = RecentDocumentsPlugin()
        PluginManager.shared.register(recentDocumentsPlugin)
        
        let createDocumentPlugin = CreateDocumentPlugin()
        PluginManager.shared.register(createDocumentPlugin)
    }
    
    private func registerUtilityPlugins() {
        let screenshotPlugin = ScreenshotPlugin()
        PluginManager.shared.register(screenshotPlugin)
        
        let screenRecordingPlugin = ScreenRecordingPlugin()
        PluginManager.shared.register(screenRecordingPlugin)
        
        let quickNotePlugin = QuickNotePlugin()
        PluginManager.shared.register(quickNotePlugin)
    }
    
    private func registerWindowManagementPlugins() {
        let showAllWindowsPlugin = ShowAllWindowsPlugin()
        PluginManager.shared.register(showAllWindowsPlugin)
        
        let hideAllWindowsPlugin = HideAllWindowsPlugin()
        PluginManager.shared.register(hideAllWindowsPlugin)
        
        let toggleWindowPlugin = ToggleWindowPlugin()
        PluginManager.shared.register(toggleWindowPlugin)
    }
    
    func loadCustomPlugins(from directory: URL) {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            Logger.shared.log("📁 自定义插件目录不存在: \(directory.path)")
            return
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let pluginFiles = contents.filter { $0.pathExtension == "plugin" }
            
            for file in pluginFiles {
                loadCustomPlugin(from: file)
            }
            
            Logger.shared.log("📦 已加载 \(pluginFiles.count) 个自定义插件")
        } catch {
            Logger.shared.log("❌ 加载自定义插件失败: \(error.localizedDescription)")
        }
    }
    
    private func loadCustomPlugin(from url: URL) {
        Logger.shared.log("📦 加载自定义插件: \(url.lastPathComponent)")
    }
}