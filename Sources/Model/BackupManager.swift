import Foundation
import AppKit

/// 备份管理器
@MainActor
class BackupManager {
    static let shared = BackupManager()
    
    private var backupTimer: Timer?
    private let backupFolderPrefix = "AIX_Backup_"
    
    private init() {
        // 应用启动时检查是否需要恢复定时备份
        if BackupConfigManager.shared.config.isEnabled {
            scheduleNextBackup()
        }
        
        // 监听应用启动和唤醒事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidFinishLaunching),
            name: NSApplication.didFinishLaunchingNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func applicationDidFinishLaunching() {
        checkAndPerformBackup()
    }
    
    @objc private func applicationWillTerminate() {
        cancelScheduledBackup()
    }
    
    // MARK: - 备份操作
    
    /// 执行备份
    /// - Parameter path: 备份路径，如果为 nil 则使用配置中的路径
    /// - Returns: 备份文件夹路径
    @discardableResult
    func performBackup(to customPath: String? = nil) throws -> String {
        let config = BackupConfigManager.shared.config
        let backupRootPath = customPath ?? config.backupPath
        
        guard !backupRootPath.isEmpty else {
            throw BackupError.noBackupPath
        }
        
        let fm = FileManager.default
        
        // 确保备份根目录存在
        if !fm.fileExists(atPath: backupRootPath) {
            try fm.createDirectory(atPath: backupRootPath, withIntermediateDirectories: true)
        }
        
        // 创建备份子文件夹
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
        let backupFolderName = "\(backupFolderPrefix)\(timestamp)"
        let backupFolderPath = (backupRootPath as NSString).appendingPathComponent(backupFolderName)
        
        try fm.createDirectory(atPath: backupFolderPath, withIntermediateDirectories: true)
        
        // 1. 复制数据库文件
        let dbPath = AppDatabase.shared.dbPath
        let dbFileName = (dbPath as NSString).lastPathComponent
        let targetDbPath = (backupFolderPath as NSString).appendingPathComponent(dbFileName)
        
        try fm.copyItem(atPath: dbPath, toPath: targetDbPath)
        
        // 复制 WAL 和 SHM 文件
        for suffix in ["-wal", "-shm"] {
            let sourcePath = dbPath + suffix
            if fm.fileExists(atPath: sourcePath) {
                let targetPath = targetDbPath + suffix
                try fm.copyItem(atPath: sourcePath, toPath: targetPath)
            }
        }
        
        // 2. 导出配置到 JSON
        let configJson = try exportAllConfigs()
        let configPath = (backupFolderPath as NSString).appendingPathComponent("config.json")
        try configJson.write(toFile: configPath, atomically: true, encoding: .utf8)
        
        // 3. 复制剪贴板历史
        let clipboardHistoryURL = ClipboardManager.shared.clipboardHistoryFileURL
        if fm.fileExists(atPath: clipboardHistoryURL.path) {
            let targetClipboard = (backupFolderPath as NSString).appendingPathComponent("clipboard_history.json")
            try fm.copyItem(atPath: clipboardHistoryURL.path, toPath: targetClipboard)
        }
        
        // 4. 复制剪贴板图片缓存目录
        let clipCacheDir = ClipboardItem.cacheDirectory
        if fm.fileExists(atPath: clipCacheDir.path) {
            let targetClipCache = (backupFolderPath as NSString).appendingPathComponent("clipboard_cache")
            try fm.copyItem(atPath: clipCacheDir.path, toPath: targetClipCache)
        }
        
        // 5. 复制 TTS 语音缓存目录
        let ttsCacheDir = TTSCacheManager.cacheDirectory
        if fm.fileExists(atPath: ttsCacheDir.path) {
            let targetTtsCache = (backupFolderPath as NSString).appendingPathComponent("tts_cache")
            try fm.copyItem(atPath: ttsCacheDir.path, toPath: targetTtsCache)
        }
        
        // 6. 创建备份清单
        let manifest = try createManifest(backupPath: backupFolderName)
        let manifestJson = try JSONEncoder().encode(manifest)
        let manifestPath = (backupFolderPath as NSString).appendingPathComponent("manifest.json")
        try manifestJson.write(to: URL(fileURLWithPath: manifestPath))
        
        // 7. 更新上次备份时间
        BackupConfigManager.shared.updateLastBackupTime(Date())
        
        // 8. 清理旧备份
        if customPath == nil {
            try? cleanOldBackups()
        }
        
        Logger.shared.log("备份完成: \(backupFolderPath)")
        return backupFolderPath
    }
    
    /// 导出所有配置
    private func exportAllConfigs() throws -> String {
        let store = AppDatabase.shared.settingsStore
        
        // 获取所有配置
        var allConfigs: [String: Any] = [:]
        
        // 已知的配置键
        let configKeys = [
            "floatingButtonConfig",
            "reminderConfig",
            "smartReminderConfig",
            "pluginConfigs",
            "useSmartReminder",
            "isFirstLaunch",
            "appExitTime",
            "smartReminderState",
            "backupConfig"
        ]
        
        for key in configKeys {
            if let value = store.loadConfig(key: key) {
                // 尝试解析 JSON 字符串
                if let data = value.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    allConfigs[key] = json
                } else {
                    // 非 JSON 格式，直接存储
                    allConfigs[key] = value
                }
            }
        }
        
        let data = try JSONSerialization.data(withJSONObject: allConfigs, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    /// 创建备份清单
    private func createManifest(backupPath: String) throws -> BackupManifest {
        let notes = AppDatabase.shared.noteStore.getAllNotes()
        let groups = AppDatabase.shared.noteStore.getAllGroups()
        
        var files = ["notes.sqlite", "config.json", "manifest.json"]
        
        let clipboardCount = ClipboardManager.shared.history.count
        if clipboardCount > 0 {
            files.append("clipboard_history.json")
            files.append("clipboard_cache")
        }
        
        let ttsCacheCount = TTSCacheManager.shared.entries.count
        if ttsCacheCount > 0 {
            files.append("tts_cache")
        }
        
        return BackupManifest(
            version: BackupManifest.currentVersion,
            appVersion: BackupManifest.appVersion,
            backupTime: Date(),
            files: files,
            noteCount: notes.count,
            groupCount: groups.count,
            clipboardCount: clipboardCount,
            ttsCacheCount: ttsCacheCount,
            backupPath: backupPath
        )
    }
    
    /// 清理旧备份
    private func cleanOldBackups() throws {
        let config = BackupConfigManager.shared.config
        let backupRootPath = config.backupPath
        
        guard !backupRootPath.isEmpty else { return }
        
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupRootPath) else { return }
        
        // 获取所有备份文件夹
        let contents = try fm.contentsOfDirectory(atPath: backupRootPath)
        let backupFolders = contents
            .filter { $0.hasPrefix(backupFolderPrefix) }
            .sorted(by: >) // 按名称降序排列（最新的在前）
        
        // 删除超过上限的旧备份
        let maxBackups = config.maxBackups
        if backupFolders.count > maxBackups {
            for i in maxBackups..<backupFolders.count {
                let folderToDelete = (backupRootPath as NSString).appendingPathComponent(backupFolders[i])
                try fm.removeItem(atPath: folderToDelete)
                Logger.shared.log("已删除旧备份: \(backupFolders[i])")
            }
        }
    }
    
    // MARK: - 定时备份
    
    /// 安排下次备份
    func scheduleNextBackup() {
        cancelScheduledBackup()
        
        let config = BackupConfigManager.shared.config
        
        guard config.isEnabled, config.frequency != .manual else { return }
        
        guard let nextTime = config.nextBackupTime() else { return }
        
        let interval = nextTime.timeIntervalSince(Date())
        
        guard interval > 0 else {
            // 已经过了今天的备份时间，立即执行
            checkAndPerformBackup()
            return
        }
        
        Logger.shared.log("下次备份时间: \(nextTime)")
        
        backupTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndPerformBackup()
            }
        }
        
        RunLoop.current.add(backupTimer!, forMode: .common)
    }
    
    /// 取消定时备份
    func cancelScheduledBackup() {
        backupTimer?.invalidate()
        backupTimer = nil
    }
    
    /// 检查并执行备份
    private func checkAndPerformBackup() {
        let config = BackupConfigManager.shared.config
        
        guard config.isEnabled, config.frequency != .manual else { return }
        
        // 检查是否需要备份
        if let lastBackup = config.lastBackupTime {
            let calendar = Calendar.current
            let now = Date()
            
            switch config.frequency {
            case .manual:
                return
            case .daily:
                // 如果今天已经备份过，跳过
                if calendar.isDate(lastBackup, inSameDayAs: now) {
                    scheduleNextBackup()
                    return
                }
            case .weekly:
                // 如果本周已经备份过，跳过
                if calendar.isDate(lastBackup, equalTo: now, toGranularity: .weekOfYear) {
                    scheduleNextBackup()
                    return
                }
            case .monthly:
                // 如果本月已经备份过，跳过
                if calendar.isDate(lastBackup, equalTo: now, toGranularity: .month) {
                    scheduleNextBackup()
                    return
                }
            }
        }
        
        // 执行备份
        do {
            try performBackup()
        } catch {
            Logger.shared.log("自动备份失败: \(error.localizedDescription)")
        }
        
        // 安排下次备份
        scheduleNextBackup()
    }
    
    // MARK: - 恢复操作
    
    /// 获取所有可用的备份
    func getAvailableBackups() -> [BackupInfo] {
        let config = BackupConfigManager.shared.config
        let backupRootPath = config.backupPath
        
        guard !backupRootPath.isEmpty else { return [] }
        
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupRootPath) else { return [] }
        
        let contents: [String]
        do {
            contents = try fm.contentsOfDirectory(atPath: backupRootPath)
        } catch {
            return []
        }
        
        var backups: [BackupInfo] = []
        
        for folder in contents where folder.hasPrefix(backupFolderPrefix) {
            let folderPath = (backupRootPath as NSString).appendingPathComponent(folder)
            let manifestPath = (folderPath as NSString).appendingPathComponent("manifest.json")
            
            var info = BackupInfo(
                path: folderPath,
                name: folder,
                date: nil,
                noteCount: 0,
                groupCount: 0,
                appVersion: nil,
                isValid: false
            )
            
            // 尝试读取清单
            if let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
               let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) {
                info.date = manifest.backupTime
                info.noteCount = manifest.noteCount
                info.groupCount = manifest.groupCount
                info.appVersion = manifest.appVersion
                info.isValid = true
            } else {
                // 没有清单，使用文件夹修改时间
                if let attrs = try? fm.attributesOfItem(atPath: folderPath),
                   let modDate = attrs[.modificationDate] as? Date {
                    info.date = modDate
                }
            }
            
            // 检查数据库文件是否存在
            let dbPath = (folderPath as NSString).appendingPathComponent("notes.sqlite")
            info.isValid = fm.fileExists(atPath: dbPath)
            
            backups.append(info)
        }
        
        // 按日期降序排列
        return backups.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
    
    /// 从备份恢复
    /// - Parameter backupInfo: 备份信息
    func restore(from backupInfo: BackupInfo) throws {
        let fm = FileManager.default
        
        guard backupInfo.isValid else {
            throw BackupError.invalidBackup
        }
        
        // 1. 先备份当前数据
        let currentBackupPath = try AppDatabase.shared.backupCurrentDatabase()
        Logger.shared.log("已备份当前数据到: \(currentBackupPath)")
        
        // 2. 恢复数据库
        let sourceDbPath = (backupInfo.path as NSString).appendingPathComponent("notes.sqlite")
        let targetDbPath = AppDatabase.shared.dbPath
        
        // 关闭当前数据库连接
        try AppDatabase.shared.switchDatabase(to: ":memory:")
        
        // 复制备份的数据库文件
        try fm.removeItem(atPath: targetDbPath)
        try fm.copyItem(atPath: sourceDbPath, toPath: targetDbPath)
        
        // 复制 WAL 和 SHM 文件
        for suffix in ["-wal", "-shm"] {
            let sourcePath = sourceDbPath + suffix
            let targetPath = targetDbPath + suffix
            if fm.fileExists(atPath: sourcePath) {
                if fm.fileExists(atPath: targetPath) {
                    try fm.removeItem(atPath: targetPath)
                }
                try fm.copyItem(atPath: sourcePath, toPath: targetPath)
            }
        }
        
        // 3. 恢复配置
        let configPath = (backupInfo.path as NSString).appendingPathComponent("config.json")
        if fm.fileExists(atPath: configPath),
           let configData = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
            try restoreConfigs(configJson)
        }
        
        // 4. 恢复剪贴板历史
        let backupClipboardPath = (backupInfo.path as NSString).appendingPathComponent("clipboard_history.json")
        if fm.fileExists(atPath: backupClipboardPath) {
            let targetURL = ClipboardManager.shared.clipboardHistoryFileURL
            if fm.fileExists(atPath: targetURL.path) {
                try fm.removeItem(at: targetURL)
            }
            try fm.copyItem(atPath: backupClipboardPath, toPath: targetURL.path)
        }
        
        // 5. 恢复剪贴板图片缓存
        let backupClipCachePath = (backupInfo.path as NSString).appendingPathComponent("clipboard_cache")
        if fm.fileExists(atPath: backupClipCachePath) {
            let targetDir = ClipboardItem.cacheDirectory
            if fm.fileExists(atPath: targetDir.path) {
                try fm.removeItem(at: targetDir)
            }
            try fm.copyItem(atPath: backupClipCachePath, toPath: targetDir.path)
        }
        
        // 6. 恢复 TTS 语音缓存
        let backupTtsCachePath = (backupInfo.path as NSString).appendingPathComponent("tts_cache")
        if fm.fileExists(atPath: backupTtsCachePath) {
            let targetDir = TTSCacheManager.cacheDirectory
            if fm.fileExists(atPath: targetDir.path) {
                try fm.removeItem(at: targetDir)
            }
            try fm.copyItem(atPath: backupTtsCachePath, toPath: targetDir.path)
        }
        
        // 7. 重新打开数据库
        try AppDatabase.shared.switchDatabase(to: targetDbPath)
        
        Logger.shared.log("已从备份恢复: \(backupInfo.name)")
        
        // 发送通知
        NotificationCenter.default.post(name: .backupDidRestore, object: nil)
    }
    
    /// 恢复配置
    private func restoreConfigs(_ configJson: [String: Any]) throws {
        let store = AppDatabase.shared.settingsStore
        
        for (key, value) in configJson {
            // 将值转换为 JSON 字符串
            let jsonData = try JSONSerialization.data(withJSONObject: value)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { continue }
            
            try store.saveConfig(key: key, value: jsonString)
        }
    }
}

// MARK: - 辅助类型

/// 备份错误
enum BackupError: Error, LocalizedError {
    case noBackupPath
    case invalidBackup
    case backupFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noBackupPath:
            return L10n.tr("backup.pathNotSet")
        case .invalidBackup:
            return L10n.tr("backup.invalidFile")
        case .backupFailed(let message):
            return L10n.tr("backup.failedTemplate", message)
        }
    }
}

/// 备份信息
struct BackupInfo: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    var date: Date?
    var noteCount: Int
    var groupCount: Int
    var appVersion: String?
    var isValid: Bool
    
    var displayName: String {
        if let date = date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: date)
        }
        return name
    }
}

// MARK: - 通知

extension Notification.Name {
    static let backupDidRestore = Notification.Name("backupDidRestore")
}
