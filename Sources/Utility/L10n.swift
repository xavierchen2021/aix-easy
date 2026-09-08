import Foundation

/// 支持的语言
enum AppLanguage: String, CaseIterable, Codable {
    case system = "system"   // 跟随系统
    case zh = "zh"           // 中文
    case en = "en"           // English
    
    var displayName: String {
        switch self {
        case .system: return "跟随系统 / System"
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

/// 本地化辅助工具
enum L10n {
    /// 当前语言 bundle 缓存（使用 NSLock 保证线程安全）
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _cachedBundle: Bundle?
    nonisolated(unsafe) private static var _cachedLanguage: String?
    
    /// 获取当前应该使用的语言代码
    private static var currentLanguageCode: String {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if saved != "system" {
            return saved
        }
        // 跟随系统
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh") {
            return "zh"
        }
        return "en"
    }
    
    /// 获取当前语言的 bundle
    private static var localizedBundle: Bundle {
        lock.lock()
        defer { lock.unlock() }
        
        let lang = currentLanguageCode
        if lang == _cachedLanguage, let bundle = _cachedBundle {
            return bundle
        }
        
        if let path = Bundle.module.path(forResource: lang, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            _cachedBundle = bundle
            _cachedLanguage = lang
            return bundle
        }
        
        // 回退到 module bundle
        _cachedBundle = Bundle.module
        _cachedLanguage = lang
        return Bundle.module
    }
    
    /// 清除缓存（语言切换时调用）
    static func clearCache() {
        lock.lock()
        _cachedBundle = nil
        _cachedLanguage = nil
        lock.unlock()
    }
    
    /// 获取本地化字符串
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: localizedBundle, comment: "")
    }
    
    /// 获取带参数的本地化字符串
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: localizedBundle, comment: "")
        return String(format: format, arguments: args)
    }
}
