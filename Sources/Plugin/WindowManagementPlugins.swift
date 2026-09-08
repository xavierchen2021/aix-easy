import Foundation
import AppKit

class ShowAllWindowsPlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.show-all-windows",
            displayName: L10n.tr("plugin.showAllWindows"),
            iconName: "rectangle.stack",
            description: L10n.tr("plugin.showAllWindowsDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("🪟 执行显示所有窗口操作")
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowAllWindows"),
            object: nil,
            userInfo: nil
        )
    }
}

class HideAllWindowsPlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.hide-all-windows",
            displayName: L10n.tr("plugin.hideAllWindows"),
            iconName: "eye.slash",
            description: L10n.tr("plugin.hideAllWindowsDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("👁️ 执行隐藏所有窗口操作")
        NotificationCenter.default.post(
            name: NSNotification.Name("HideAllWindows"),
            object: nil,
            userInfo: nil
        )
    }
}

class ToggleWindowPlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.toggle-window",
            displayName: L10n.tr("plugin.toggleWindow"),
            iconName: "arrow.triangle.2.circlepath",
            description: L10n.tr("plugin.toggleWindowDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("🔄 执行切换窗口操作")
        guard let sender = context.sender as? GlowFloatingButtonView else {
            Logger.shared.log("⚠️ 无法获取悬浮球视图")
            return
        }
        
        WindowManager.shared.handleToggleWindow(for: sender.buttonIndex)
    }
}
