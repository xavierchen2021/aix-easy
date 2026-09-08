import Foundation
import AppKit

protocol PluginAction: AnyObject {
    var pluginId: String { get }
    var displayName: String { get }
    var iconName: String? { get }
    var description: String { get }
    var isEnabled: Bool { get set }
    
    @MainActor
    func execute(context: PluginContext) throws
}

struct PluginContext {
    let sender: Any?
    let window: NSWindow?
    let userInfo: [String: Any]?
    
    init(sender: Any? = nil, window: NSWindow? = nil, userInfo: [String: Any]? = nil) {
        self.sender = sender
        self.window = window
        self.userInfo = userInfo
    }
}

enum PluginError: Error, LocalizedError {
    case pluginNotFound(String)
    case pluginExecutionFailed(String)
    case pluginDisabled(String)
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .pluginNotFound(let id):
            return L10n.tr("pluginError.notFound", id)
        case .pluginExecutionFailed(let id):
            return L10n.tr("pluginError.failed", id)
        case .pluginDisabled(let id):
            return L10n.tr("pluginError.disabled", id)
        case .invalidConfiguration:
            return L10n.tr("pluginError.invalidConfig")
        }
    }
}
