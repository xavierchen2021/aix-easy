import Foundation
import AppKit

class ScreenshotPlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.screenshot",
            displayName: L10n.tr("plugin.screenshot"),
            iconName: "camera",
            description: L10n.tr("plugin.screenshotDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("📷 执行截图操作")
        NotificationCenter.default.post(
            name: NSNotification.Name("TakeScreenshot"),
            object: nil,
            userInfo: nil
        )
    }
}

class ScreenRecordingPlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.screen-recording",
            displayName: L10n.tr("plugin.screenRecording"),
            iconName: "video",
            description: L10n.tr("plugin.screenRecordingDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("🎥 执行录屏操作")
        NotificationCenter.default.post(
            name: NSNotification.Name("StartRecording"),
            object: nil,
            userInfo: nil
        )
    }
}

class QuickNotePlugin: BasePlugin {
    init() {
        super.init(
            pluginId: "com.notemaster.plugin.quick-note",
            displayName: L10n.tr("plugin.quickNote"),
            iconName: "pencil",
            description: L10n.tr("plugin.quickNoteDesc")
        )
    }
    
    override func execute(context: PluginContext) throws {
        Logger.shared.log("✏️ 执行快速笔记操作")
        guard let window = context.window else {
            Logger.shared.log("⚠️ 无法获取窗口上下文")
            return
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("QuickNote"),
            object: nil,
            userInfo: ["window": window]
        )
    }
}
