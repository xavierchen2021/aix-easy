import Foundation
import AppKit

struct BrowserInfo: Identifiable {
    let id: String // bundle identifier
    let name: String
    let icon: NSImage
    let url: URL // app URL
}

@MainActor
class BrowserDetector {
    static let shared = BrowserDetector()
    
    /// 检查 AIX 是否为系统默认浏览器（默认 HTTPS handler）
    func isDefaultBrowser() -> Bool {
        let selfBundleId = (Bundle.main.bundleIdentifier ?? "com.xavier.aix").lowercased()
        guard let httpsURL = URL(string: "https://example.com"),
              let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: httpsURL),
              let defaultBundle = Bundle(url: defaultAppURL),
              let defaultBundleId = defaultBundle.bundleIdentifier?.lowercased() else {
            return false
        }
        return defaultBundleId == selfBundleId
    }
    
    /// 获取系统中所有注册了 HTTP/HTTPS 的浏览器（排除自身），应用隐藏和排序配置
    func detectBrowsers() -> [BrowserInfo] {
        let config = FloatingButtonConfigManager.shared.config
        let allBrowsers = detectAllBrowsers()
        
        // 过滤隐藏的浏览器
        let visible = allBrowsers.filter { !config.hiddenBrowsers.contains($0.id) }
        
        // 应用自定义排序
        if config.browserOrder.isEmpty {
            return visible
        }
        
        return visible.sorted { a, b in
            let indexA = config.browserOrder.firstIndex(of: a.id) ?? Int.max
            let indexB = config.browserOrder.firstIndex(of: b.id) ?? Int.max
            if indexA != indexB { return indexA < indexB }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    
    /// 获取所有浏览器（不过滤，供设置界面使用）
    func detectAllBrowsers() -> [BrowserInfo] {
        let selfBundleId = Bundle.main.bundleIdentifier ?? "com.xavier.aix"
        var seen = Set<String>()
        var browsers: [BrowserInfo] = []
        
        // 使用 NSWorkspace API 获取所有 https handler
        let httpsURL = URL(string: "https://example.com")!
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: httpsURL)
        
        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier else { continue }
            let lower = bundleId.lowercased()
            guard lower != selfBundleId.lowercased(), !seen.contains(lower) else { continue }
            seen.insert(lower)
            
            if let info = browserInfo(for: bundleId) {
                browsers.append(info)
            }
        }
        
        // 按名称排序
        browsers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return browsers
    }
    
    /// 用指定浏览器打开 URL
    func openURL(_ url: URL, with browser: BrowserInfo) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: browser.url, configuration: config) { _, error in
            Task { @MainActor in
                if let error = error {
                    Logger.shared.log("❌ 用 \(browser.name) 打开 URL 失败: \(error.localizedDescription)")
                } else {
                    Logger.shared.log("✅ 已用 \(browser.name) 打开: \(url.absoluteString)")
                }
            }
        }
    }
    
    private func browserInfo(for bundleId: String) -> BrowserInfo? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        
        let name: String
        if let bundle = Bundle(url: appURL),
           let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            name = displayName
        } else {
            name = appURL.deletingPathExtension().lastPathComponent
        }
        
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 48, height: 48)
        
        return BrowserInfo(id: bundleId, name: name, icon: icon, url: appURL)
    }
}
