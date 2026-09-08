import Foundation
import AppKit

class OpenDocumentPlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.open-document",
            displayName: L10n.tr("plugin.openDocument"),
            iconName: "doc.text",
            description: L10n.tr("plugin.openDocumentDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("📄 执行打开文档操作")
        guard let window = context.window else {
            Logger.shared.log("⚠️ 无法获取窗口上下文")
            return
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenDocumentManager"),
            object: nil,
            userInfo: ["window": window]
        )
    }
}

class SearchDocumentPlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.search-document",
            displayName: L10n.tr("plugin.searchDocuments"),
            iconName: "magnifyingglass",
            description: L10n.tr("plugin.searchDocumentsDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("🔍 执行搜索文档操作")
        guard let window = context.window else {
            Logger.shared.log("⚠️ 无法获取窗口上下文")
            return
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("SearchDocuments"),
            object: nil,
            userInfo: ["window": window]
        )
    }
}

class RecentDocumentsPlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.recent-documents",
            displayName: L10n.tr("plugin.recentDocuments"),
            iconName: "clock",
            description: L10n.tr("plugin.recentDocumentsDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("🕐 执行查看最近文档操作")
        guard let window = context.window else {
            Logger.shared.log("⚠️ 无法获取窗口上下文")
            return
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowRecentDocuments"),
            object: nil,
            userInfo: ["window": window]
        )
    }
}

class CreateDocumentPlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.create-document",
            displayName: L10n.tr("plugin.newDocument"),
            iconName: "plus.square",
            description: L10n.tr("plugin.newDocumentDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("➕ 执行新建文档操作")
        guard let window = context.window else {
            Logger.shared.log("⚠️ 无法获取窗口上下文")
            return
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("CreateDocument"),
            object: nil,
            userInfo: ["window": window]
        )
    }
}
