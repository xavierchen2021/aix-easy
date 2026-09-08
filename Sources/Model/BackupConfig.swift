import Foundation

/// 备份频率选项
enum BackupFrequency: String, Codable, CaseIterable {
    case manual = "手动"
    case daily = "每天"
    case weekly = "每周"
    case monthly = "每月"
    
    var localizedName: String {
        switch self {
        case .manual: return L10n.tr("backup.manual")
        case .daily: return L10n.tr("backup.daily")
        case .weekly: return L10n.tr("backup.weekly")
        case .monthly: return L10n.tr("backup.monthly")
        }
    }

    var displayName: String {
        return localizedName
    }
}

/// 备份配置
struct BackupConfig: Codable {
    /// 是否启用自动备份
    var isEnabled: Bool
    /// 备份频率
    var frequency: BackupFrequency
    /// 备份路径
    var backupPath: String
    /// 最大备份数量
    var maxBackups: Int
    /// 上次备份时间
    var lastBackupTime: Date?
    /// 备份时间（小时，0-23）
    var backupHour: Int
    /// 备份时间（分钟，0-59）
    var backupMinute: Int
    
    /// 默认配置
    static let `default` = BackupConfig(
        isEnabled: false,
        frequency: .daily,
        backupPath: "",
        maxBackups: 10,
        lastBackupTime: nil,
        backupHour: 3,
        backupMinute: 0
    )
    
    /// 获取下次备份时间
    func nextBackupTime() -> Date? {
        guard isEnabled, !backupPath.isEmpty else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        var components = DateComponents()
        components.hour = backupHour
        components.minute = backupMinute
        components.second = 0
        
        guard let todayBackup = calendar.date(bySettingHour: backupHour, minute: backupMinute, second: 0, of: now) else {
            return nil
        }
        
        switch frequency {
        case .manual:
            return nil
        case .daily:
            if todayBackup > now {
                return todayBackup
            } else {
                return calendar.date(byAdding: .day, value: 1, to: todayBackup)
            }
        case .weekly:
            let weekday = calendar.component(.weekday, from: now)
            let daysUntilNextWeek = weekday <= 2 ? (2 - weekday) : (9 - weekday)
            if daysUntilNextWeek == 0 && todayBackup > now {
                return todayBackup
            }
            return calendar.date(byAdding: .day, value: daysUntilNextWeek == 0 ? 7 : daysUntilNextWeek, to: todayBackup)
        case .monthly:
            let day = calendar.component(.day, from: now)
            if day == 1 && todayBackup > now {
                return todayBackup
            }
            let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            let daysUntilNextMonth = daysInMonth - day + 1
            return calendar.date(byAdding: .day, value: daysUntilNextMonth, to: todayBackup)
        }
    }
}

/// 备份清单
struct BackupManifest: Codable {
    /// 备份版本
    let version: String
    /// 应用版本
    let appVersion: String
    /// 备份时间
    let backupTime: Date
    /// 备份文件列表
    let files: [String]
    /// 笔记数量
    let noteCount: Int
    /// 分组数量
    let groupCount: Int
    /// 剪贴板条目数（v1.1 新增）
    var clipboardCount: Int
    /// TTS 缓存条目数（v1.1 新增）
    var ttsCacheCount: Int
    /// 备份路径（相对于备份根目录）
    let backupPath: String
    
    /// 当前备份版本
    static let currentVersion = "1.1"
    
    /// 获取应用版本号
    static var appVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    /// 向后兼容解码：旧备份缺少 clipboardCount/ttsCacheCount 字段时使用默认值 0
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        backupTime = try container.decode(Date.self, forKey: .backupTime)
        files = try container.decode([String].self, forKey: .files)
        noteCount = try container.decode(Int.self, forKey: .noteCount)
        groupCount = try container.decode(Int.self, forKey: .groupCount)
        clipboardCount = try container.decodeIfPresent(Int.self, forKey: .clipboardCount) ?? 0
        ttsCacheCount = try container.decodeIfPresent(Int.self, forKey: .ttsCacheCount) ?? 0
        backupPath = try container.decode(String.self, forKey: .backupPath)
    }
    
    init(version: String, appVersion: String, backupTime: Date, files: [String],
         noteCount: Int, groupCount: Int, clipboardCount: Int, ttsCacheCount: Int,
         backupPath: String) {
        self.version = version
        self.appVersion = appVersion
        self.backupTime = backupTime
        self.files = files
        self.noteCount = noteCount
        self.groupCount = groupCount
        self.clipboardCount = clipboardCount
        self.ttsCacheCount = ttsCacheCount
        self.backupPath = backupPath
    }
}

/// 备份配置管理器
@MainActor
class BackupConfigManager: ObservableObject {
    static let shared = BackupConfigManager()
    
    private let configKey = "backupConfig"
    private let store: SettingsStore
    
    @Published var config: BackupConfig
    
    private init() {
        self.store = AppDatabase.shared.settingsStore
        
        // 从数据库加载配置
        if let jsonString = store.loadConfig(key: configKey),
           let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(BackupConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }
    
    /// 保存配置
    func save() {
        if let data = try? JSONEncoder().encode(config),
           let str = String(data: data, encoding: .utf8) {
            try? store.saveConfig(key: configKey, value: str)
        }
    }
    
    /// 更新启用状态
    func updateEnabled(_ enabled: Bool) {
        config.isEnabled = enabled
        save()
        
        if enabled {
            BackupManager.shared.scheduleNextBackup()
        } else {
            BackupManager.shared.cancelScheduledBackup()
        }
    }
    
    /// 更新备份频率
    func updateFrequency(_ frequency: BackupFrequency) {
        config.frequency = frequency
        save()
        
        if config.isEnabled {
            BackupManager.shared.scheduleNextBackup()
        }
    }
    
    /// 更新备份路径
    func updateBackupPath(_ path: String) {
        config.backupPath = path
        save()
    }
    
    /// 更新最大备份数
    func updateMaxBackups(_ count: Int) {
        config.maxBackups = max(1, min(count, 100))
        save()
    }
    
    /// 更新备份时间
    func updateBackupTime(hour: Int, minute: Int) {
        config.backupHour = max(0, min(hour, 23))
        config.backupMinute = max(0, min(minute, 59))
        save()
        
        if config.isEnabled {
            BackupManager.shared.scheduleNextBackup()
        }
    }
    
    /// 更新上次备份时间
    func updateLastBackupTime(_ time: Date) {
        config.lastBackupTime = time
        save()
    }
}
