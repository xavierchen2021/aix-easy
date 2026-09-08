import Cocoa
import AppKit

@MainActor
class ColorPickerManager {
    static let shared = ColorPickerManager()
    
    private let sampler = NSColorSampler()
    
    private init() {}
    
    func startPicking() {
        Logger.shared.log("🎨 开始取色...")
        sampler.show { [weak self] color in
            Task { @MainActor in
                guard let self = self, let color = color else {
                    Logger.shared.log("🎨 取色取消或失败")
                    return
                }
                
                self.handlePickedColor(color)
            }
        }
    }
    
    private func handlePickedColor(_ color: NSColor) {
        // 转换颜色为 Hex 格式
        guard let rgbColor = color.usingColorSpace(.sRGB) else { return }
        
        let red = Int(rgbColor.redComponent * 255)
        let green = Int(rgbColor.greenComponent * 255)
        let blue = Int(rgbColor.blueComponent * 255)
        
        let hexString = String(format: "#%02X%02X%02X", red, green, blue)
        Logger.shared.log("🎨 取得颜色: \(hexString)")
        
        // 使用 NoteManager 保存以确保 UI 同步
        NoteManager.shared.addNote(content: hexString, groupId: NoteGroup.colorGroupId, colorHex: hexString)
        
        // 自动复制最新 Hex 到剪切板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hexString, forType: .string)
        
        Logger.shared.log("✅ 颜色已保存到数据库并同步到 UI，已复制到剪切板")
    }
}
