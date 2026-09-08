import Foundation

/// 应用版本号（打包脚本会自动替换此值）
enum AppVersion {
    static let current = "1.0.15"
    
    /// 从 Bundle 获取版本号，优先使用 Info.plist 中的值
    static var display: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? current
    }
}
