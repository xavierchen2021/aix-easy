import Foundation
import AppKit

/// 自动隐藏管理器
/// 监控所有运行中的应用，当某个应用超过设定时间未被激活时自动隐藏
@MainActor
class AutoHideManager {
    static let shared = AutoHideManager()
    
    // MARK: - 配置
    
    /// 是否启用自动隐藏
    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                start()
            } else {
                stop()
            }
            saveConfig()
        }
    }
    
    /// 超时时间（秒）
    var timeout: TimeInterval = 1200 { // 默认 20 分钟
        didSet { saveConfig() }
    }
    
    /// 排除的应用 Bundle ID 列表
    var excludedApps: Set<String> = [] {
        didSet { saveConfig() }
    }
    
    /// 加载配置期间抑制 didSet 中的 saveConfig
    private var isLoading: Bool = false
    
    // MARK: - 内部状态
    
    /// 每个应用的最后活跃时间 [bundleId: lastActiveTime]
    private var lastActiveTimes: [String: Date] = [:]
    
    /// 轮询定时器
    private var timer: Timer?
    
    /// 工作区通知观察者
    private var activationObserver: Any?
    
    /// 默认排除的系统应用
    private let systemExcludedApps: Set<String> = [
        "com.apple.finder",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.SystemUIServer",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.xavier.aix"
    ]
    
    private let configKeyEnabled = "autoHide_enabled"
    private let configKeyTimeout = "autoHide_timeout"
    private let configKeyExcluded = "autoHide_excludedApps"
    
    // MARK: - 初始化
    
    private init() {
        loadConfig()
        if isEnabled {
            start()
        }
    }
    
    // MARK: - 启动 / 停止
    
    private func start() {
        guard activationObserver == nil else { return }
        
        // 记录当前前台应用
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontApp.bundleIdentifier {
            lastActiveTimes[bundleId] = Date()
        }
        
        // 监听应用激活事件
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleId = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in
                guard let self = self, let bundleId = bundleId else { return }
                self.lastActiveTimes[bundleId] = Date()
            }
        }
        
        // 启动轮询定时器（5 秒间隔）
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndHideInactiveApps()
            }
        }
        
        Logger.shared.log("🙈 自动隐藏已启动，超时: \(Int(timeout))秒")
    }
    
    private func stop() {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
        timer?.invalidate()
        timer = nil
        lastActiveTimes.removeAll()
        Logger.shared.log("🙈 自动隐藏已停止")
    }
    
    // MARK: - 核心逻辑
    
    private func checkAndHideInactiveApps() {
        let now = Date()
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            
            // 跳过排除的应用
            if systemExcludedApps.contains(bundleId) || excludedApps.contains(bundleId) {
                continue
            }
            
            // 跳过已隐藏或未激活的普通应用
            guard app.activationPolicy == .regular else { continue }
            if app.isHidden { continue }
            
            // 跳过当前前台应用
            if app.isActive { continue }
            
            // 检查是否有记录；没记录的说明是自动隐藏启动前就不活跃的，记录当前时间
            guard let lastActive = lastActiveTimes[bundleId] else {
                lastActiveTimes[bundleId] = now
                continue
            }
            
            // 超时则隐藏
            if now.timeIntervalSince(lastActive) >= timeout {
                app.hide()
                lastActiveTimes.removeValue(forKey: bundleId)
                Logger.shared.log("🙈 自动隐藏: \(app.localizedName ?? bundleId)")
            }
        }
    }
    
    // MARK: - 排除列表管理
    
    func addExcludedApp(_ bundleId: String) {
        excludedApps.insert(bundleId)
    }
    
    func removeExcludedApp(_ bundleId: String) {
        excludedApps.remove(bundleId)
    }
    
    /// 获取当前运行中可被管理的应用列表（regular activation policy）
    func getManageableApps() -> [(name: String, bundleId: String, icon: NSImage)] {
        let selfBundleId = Bundle.main.bundleIdentifier ?? "com.xavier.aix"
        var apps: [(name: String, bundleId: String, icon: NSImage)] = []
        var seen = Set<String>()
        
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  !systemExcludedApps.contains(bundleId),
                  bundleId != selfBundleId,
                  !seen.contains(bundleId) else { continue }
            seen.insert(bundleId)
            
            let name = app.localizedName ?? bundleId
            let icon = app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
            icon.size = NSSize(width: 24, height: 24)
            apps.append((name: name, bundleId: bundleId, icon: icon))
        }
        
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps
    }
    
    // MARK: - 持久化
    
    private func saveConfig() {
        guard !isLoading else { return }
        let store = AppDatabase.shared.settingsStore
        try? store.saveConfig(key: configKeyEnabled, value: isEnabled ? "1" : "0")
        try? store.saveConfig(key: configKeyTimeout, value: String(Int(timeout)))
        let excludedList = excludedApps.joined(separator: ",")
        try? store.saveConfig(key: configKeyExcluded, value: excludedList)
    }
    
    private func loadConfig() {
        isLoading = true
        let store = AppDatabase.shared.settingsStore
        if let enabledStr = store.loadConfig(key: configKeyEnabled) {
            isEnabled = enabledStr == "1"
        }
        if let timeoutStr = store.loadConfig(key: configKeyTimeout), let val = Int(timeoutStr) {
            timeout = TimeInterval(val)
        }
        if let excludedStr = store.loadConfig(key: configKeyExcluded), !excludedStr.isEmpty {
            excludedApps = Set(excludedStr.split(separator: ",").map(String.init))
        }
        isLoading = false
    }
}
