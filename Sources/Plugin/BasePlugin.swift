import Foundation
import AppKit

class BasePlugin: PluginAction {
    let pluginId: String
    let displayName: String
    let iconName: String?
    let description: String
    var isEnabled: Bool = true
    
    init(pluginId: String, displayName: String, iconName: String?, description: String) {
        self.pluginId = pluginId
        self.displayName = displayName
        self.iconName = iconName
        self.description = description
    }
    
    func execute(context: PluginContext) throws {
        fatalError("子类必须实现 execute 方法")
    }
}