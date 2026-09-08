import Foundation
import AppKit
import Combine

/// 提醒休息配置
struct ReminderConfig: Codable {
    /// 是否启用提醒
    var isEnabled: Bool
    /// 提醒间隔（分钟）
    var intervalMinutes: Int
    /// 提醒消息内容
    var message: String
    /// 提醒声音
    var soundName: String
    /// 上次提醒时间
    var lastReminderTime: Date?
    
    /// 默认配置
    static let `default` = ReminderConfig(
        isEnabled: true,
        intervalMinutes: 30,
        message: L10n.tr("reminder.defaultMessage"),
        soundName: "Glass",
        lastReminderTime: nil
    )
    
    /// 最小间隔时间（分钟）
    static let minInterval: Int = 5
    /// 最大间隔时间（分钟）
    static let maxInterval: Int = 120
}

/// 智能提醒配置
struct SmartReminderConfig: Codable {
    /// 是否启用智能提醒
    var isEnabled: Bool
    /// 工作时长（秒）
    var workDuration: TimeInterval
    /// 休息时长（秒）
    var restDuration: TimeInterval
    /// 空闲阈值（秒）
    var idleThreshold: TimeInterval
    /// 提醒消息
    var reminderMessage: String
    /// 提醒声音
    var soundName: String
    /// 休息结束提醒声音
    var restEndSoundName: String
    /// 休息认定时间（秒），触发空闲后累计超过此值则认为已休息并重置计时
    var restRecognitionTime: TimeInterval
    
    /// 默认配置
    static let `default` = SmartReminderConfig(
        isEnabled: true,
        workDuration: 2100,        // 35分钟
        restDuration: 300,         // 5分钟
        // 默认空闲阈值为 60 秒
        idleThreshold: 60,
        reminderMessage: L10n.tr("reminder.defaultMessage"),
        soundName: "Glass",
        restEndSoundName: "Glass",
        // 默认休息认定时间设为 4 分 30 秒（270 秒）
        restRecognitionTime: 270
    )
    
    /// 最小工作时长（秒）
    static let minWorkDuration: TimeInterval = 1500     // 25分钟
    /// 最大工作时长（秒）
    static let maxWorkDuration: TimeInterval = 7200     // 120分钟
    /// 最小休息时长（秒）
    static let minRestDuration: TimeInterval = 300      // 5分钟
    /// 最大休息时长（秒）
    static let maxRestDuration: TimeInterval = 900      // 15分钟
}

/// 提醒休息管理器
@MainActor
final class ReminderManager: ObservableObject, Sendable {
    static let shared = ReminderManager()

    private let configKey = "reminderConfig"
    private let smartConfigKey = "smartReminderConfig"
    private let useSmartReminderKey = "useSmartReminder"
    private let store: SettingsStore

    @Published var config: ReminderConfig
    @Published var smartConfig: SmartReminderConfig
    private var timer: Timer?
    private var isShowingAlert = false
    private var overlayWindow: ReminderOverlayWindow?
    
    /// 当外部模块感知到可能的权限变更或系统激活时，告知管理器尝试刷新
    func refreshState() {
        print("🔄 ReminderManager 刷新状态...")
        if useSmartReminder {
            if smartConfig.isEnabled && smartReminderManager == nil {
                startSmartReminderManager()
            }
        } else {
            if config.isEnabled && timer == nil {
                startTimer()
            }
        }
    }
    
    /// 是否使用智能提醒模式
    @Published var useSmartReminder: Bool = true {
        didSet {
            // Preserve the overall enabled state when switching modes.
            // If switching into smart mode, keep smartConfig.isEnabled equal to the previous mode's enabled state (and vice versa).
            let previousEnabled = oldValue ? smartConfig.isEnabled : config.isEnabled

            if useSmartReminder {
                // Switching to smart reminder mode
                if smartConfig.isEnabled != previousEnabled {
                    updateSmartEnabled(previousEnabled)
                }
            } else {
                // Switching to fixed interval mode
                if config.isEnabled != previousEnabled {
                    updateEnabled(previousEnabled)
                }
            }
        }
    }
    
    /// 智能提醒管理器
    private var smartReminderManager: SmartReminderManager?
    
    /// 标记是否需要在设置关闭时重置计时器（仅修改时间相关设置时为 true）
    private var needsTimerReset = false

    private init() {
        self.config = .default
        self.smartConfig = .default
        self.store = AppDatabase.shared.settingsStore

        // 从数据库加载配置
        if let jsonString = store.loadConfig(key: configKey),
           let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ReminderConfig.self, from: data) {
            self.config = decoded
        }
        
        // 从数据库加载智能提醒配置
        if let jsonString = store.loadConfig(key: smartConfigKey),
           let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(SmartReminderConfig.self, from: data) {
            self.smartConfig = decoded
        }

        // 强制使用智能提醒模式
        self.useSmartReminder = true

        // 监听 useSmartReminder 变化
        $useSmartReminder
            .dropFirst() // 避免初始化时的多余保存
            .sink { [weak self] newValue in
                guard let self = self else { return }
                
                // 保存模式选择
                self.save()
                
                if newValue && self.smartConfig.isEnabled && self.config.isEnabled {
                    self.startSmartReminderManager()
                } else {
                    self.smartReminderManager?.stop()
                    self.smartReminderManager = nil
                    
                    if let window = self.overlayWindow {
                        window.close()
                        self.overlayWindow = nil
                    }
                }
                
                // 重启定时器
                self.startTimer()
            }
            .store(in: &cancellables)

        // 初始化时如果默认使用智能提醒且已启用配置，则启动智能提醒管理器
        if useSmartReminder && smartConfig.isEnabled {
            if InputMonitor.hasAccessibilityPermission() {
                startSmartReminderManager()
            } else {
                // 主动提示权限不足
                NotificationCenter.default.post(name: .smartReminderNeedsPermission, object: nil)
            }
        } else if !useSmartReminder && config.isEnabled {
            // 如果不使用智能提醒但启用了普通提醒，启动普通定时器
            startTimer()
        }

        // 监听应用生命周期
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private var cancellables = Set<AnyCancellable>()


    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 配置管理
    
    private func save() {
        if let data = try? JSONEncoder().encode(config),
           let str = String(data: data, encoding: .utf8) {
            try? store.saveConfig(key: configKey, value: str)
        }
        
        if let data = try? JSONEncoder().encode(smartConfig),
           let str = String(data: data, encoding: .utf8) {
            try? store.saveConfig(key: smartConfigKey, value: str)
        }
        
        try? store.saveConfig(key: useSmartReminderKey, value: useSmartReminder ? "true" : "false")
    }
    
    /// 加载应用退出时间
    private func loadAppExitTime() -> Date? {
        guard let timeString = store.loadConfig(key: "appExitTime") else {
            return nil
        }
        return TimeInterval(timeString).flatMap { Date(timeIntervalSince1970: $0) }
    }
    
    /// 更新启用状态
    func updateEnabled(_ enabled: Bool) {
        config.isEnabled = enabled
        save()

        if enabled {
            // 如果使用智能提醒模式，启动智能提醒管理器
            if useSmartReminder {
                startSmartReminderManager()
            } else {
                startTimer()
            }
        } else {
            stopTimer()
            smartReminderManager?.stop()
            smartReminderManager = nil

            if let window = overlayWindow {
                window.close()
                overlayWindow = nil
            }
        }

        // 确保智能提醒的启用状态与普通提醒同步
        if useSmartReminder {
            if smartConfig.isEnabled != enabled {
                updateSmartEnabled(enabled)
            }
        }
    }
    
    /// 更新提醒间隔
    func updateInterval(_ minutes: Int) {
        let clamped = max(ReminderConfig.minInterval, min(minutes, ReminderConfig.maxInterval))
        config.intervalMinutes = clamped
        save()
        
        // 如果已经启用，需要重启定时器
        if config.isEnabled {
            startTimer()
        }
    }
    
    /// 更新提醒消息
    func updateMessage(_ message: String) {
        config.message = message.isEmpty ? ReminderConfig.default.message : message
        save()
    }
    
    /// 更新提醒声音
    func updateSound(_ sound: String) {
        config.soundName = sound.isEmpty ? "Glass" : sound
        save()
    }
    
    // MARK: - 智能提醒配置管理
    
    /// 更新智能提醒启用状态
    func updateSmartEnabled(_ enabled: Bool) {
        smartConfig.isEnabled = enabled
        save()

        // 智能提醒模式下，同时更新普通提醒状态
        if enabled {
            config.isEnabled = true
            // 无论之前是否已启用，都要确保智能提醒管理器重新启动
            startSmartReminderManager()
        } else {
            smartReminderManager?.stop()
            smartReminderManager = nil

            if let window = overlayWindow {
                window.close()
                overlayWindow = nil
            }
        }

        // 重启定时器
        startTimer()
    }
    
    /// 更新工作时长（分钟）
    func updateWorkDuration(_ minutes: Int) {
        let minutesDouble = Double(minutes)
        let minMinutes = SmartReminderConfig.minWorkDuration / 60
        let maxMinutes = SmartReminderConfig.maxWorkDuration / 60
        let clamped = max(minMinutes, min(minutesDouble, maxMinutes))
        let duration = TimeInterval(clamped * 60)
        smartConfig.workDuration = duration
        needsTimerReset = true
        save()

        // Propagate config change to running smart manager
        if let manager = smartReminderManager {
            manager.config = smartConfig
        }
        
        if smartConfig.isEnabled {
            startTimer()
        }
    }
    
    /// 更新休息时长（分钟）
    func updateRestDuration(_ minutes: Int) {
        let minutesDouble = Double(minutes)
        let minMinutes = SmartReminderConfig.minRestDuration / 60
        let maxMinutes = SmartReminderConfig.maxRestDuration / 60
        let clamped = max(minMinutes, min(minutesDouble, maxMinutes))
        let duration = TimeInterval(clamped * 60)
        smartConfig.restDuration = duration
        needsTimerReset = true

        // 更新与休息时长相关的衍生配置
        // 保证 restRecognitionTime 在 [0.6*restDuration, 1.0*restDuration] 之间
        let minRecognition = duration * 0.6
        let maxRecognition = duration
        if smartConfig.restRecognitionTime < minRecognition {
            smartConfig.restRecognitionTime = minRecognition
        } else if smartConfig.restRecognitionTime > maxRecognition {
            smartConfig.restRecognitionTime = maxRecognition
        }

        save()

        if let manager = smartReminderManager {
            manager.config = smartConfig
        }
    }
    

    
    /// 更新空闲阈值（秒）
    func updateIdleThreshold(_ seconds: Int) {
        // 限制在 60 到 180 秒之间
        smartConfig.idleThreshold = TimeInterval(max(60, min(seconds, 180)))
        needsTimerReset = true
        save()

        if let manager = smartReminderManager {
            manager.config = smartConfig
        }
    }
    
    /// 更新智能提醒消息
    func updateSmartReminderMessage(_ message: String) {
        smartConfig.reminderMessage = message.isEmpty ? SmartReminderConfig.default.reminderMessage : message
        save()

        if let manager = smartReminderManager {
            manager.config = smartConfig
        }
    }
    
    /// 更新智能提醒声音
    func updateSmartReminderSound(_ sound: String) {
        smartConfig.soundName = sound.isEmpty ? "Glass" : sound
        save()

        if let manager = smartReminderManager {
            manager.config = smartConfig
        }
    }

    /// 更新休息结束提醒声音
    func updateRestEndSound(_ sound: String) {
        smartConfig.restEndSoundName = sound.isEmpty ? "Glass" : sound
        save()

        if let manager = smartReminderManager {
            manager.config = smartConfig
        }
    }
    
    /// 更新休息认定时间（分钟）
    func updateRestRecognitionTime(_ minutes: Double) {
        // 将分钟转换为秒，依据当前 restDuration 限制在 [0.6*restDuration, 1.0*restDuration]
        let requested = TimeInterval(max(0.0, minutes) * 60.0)
        let minRecognition = smartConfig.restDuration * 0.6
        let maxRecognition = smartConfig.restDuration
        let clamped = max(minRecognition, min(requested, maxRecognition))
        smartConfig.restRecognitionTime = clamped
        needsTimerReset = true
        save()

        if let manager = smartReminderManager {
            manager.config = smartConfig
        }
    }
    
    // MARK: - 智能提醒管理器管理
    
    /// 当设置窗口关闭时调用，恢复/重置计时计时逻辑
    func handleSettingsClosed() {
        guard needsTimerReset else {
            print("⚙️ 设置窗口关闭，未修改时间设置，跳过重置")
            return
        }
        needsTimerReset = false
        print("⚙️ 设置窗口关闭，时间设置已修改，执行计时重置")
        if useSmartReminder && smartConfig.isEnabled {
            if let manager = smartReminderManager {
                manager.reset()
                manager.start()
            } else {
                startSmartReminderManager()
            }
        }
    }
    
    /// 启动智能提醒管理器
    private func startSmartReminderManager() {
        // 停止现有的智能提醒管理器
        smartReminderManager?.stop()
        smartReminderManager = nil

        if let window = overlayWindow {
            window.close()
            overlayWindow = nil
        }

        // 检查是否启用了智能提醒
        guard useSmartReminder && smartConfig.isEnabled else {
            return
        }

        // 检查辅助功能权限，若没有则不启动智能提醒，并通知前端展示提示
        if !InputMonitor.hasAccessibilityPermission() {
            print("⚠️ 未授予辅助功能权限，无法启动智能提醒")
            // 仅仅由于权限缺失，不应直接修改用户的配置开启状态，
            // 而是发送通知让 UI 提示用户，并停止当前尝试。
            NotificationCenter.default.post(name: .smartReminderNeedsPermission, object: nil)
            return
        }

        // 检查应用退出时间，判断是否需要恢复状态
        var shouldRestoreState = true
        if let appExitTime = loadAppExitTime() {
            let timeSinceExit = Date().timeIntervalSince(appExitTime)
            let timeKeepThreshold = smartConfig.restRecognitionTime

            if timeSinceExit >= timeKeepThreshold {
                // 超过阈值，不恢复状态
                shouldRestoreState = false
                print("⏱️ 应用关闭时间 \(Int(timeSinceExit))秒 >= 休息认定时间 \(Int(timeKeepThreshold))秒，不恢复智能提醒状态")
            } else {
                print("✅ 应用关闭时间 \(Int(timeSinceExit))秒 < 休息认定时间 \(Int(timeKeepThreshold))秒，恢复智能提醒状态")
            }
        }

        // 如果不需要恢复状态，清除保存的状态
        if !shouldRestoreState {
            try? store.saveConfig(key: "smartReminderState", value: "")
        }

        // 发布通知：智能提醒已启动（或即将启动），用于前端更新状态（可选）
        NotificationCenter.default.post(name: .smartReminderDidStart, object: nil)

        // 创建提醒窗口
        let newOverlayWindow = ReminderOverlayWindow(message: smartConfig.reminderMessage) { [weak self] in
            guard let self = self else { return }
            self.isShowingAlert = false
            self.overlayWindow = nil
        }

        // 创建智能提醒管理器
        let manager = SmartReminderManager(config: smartConfig, reminderOverlay: newOverlayWindow)
        manager.start()

        smartReminderManager = manager
        overlayWindow = newOverlayWindow

        print("✅ 智能提醒管理器已启动")
    }
    
    /// 停止智能提醒管理器
    private func stopSmartReminderManager() {
        smartReminderManager?.saveState()
        smartReminderManager?.stop()
        smartReminderManager = nil
        
        if let window = overlayWindow {
            window.close()
            overlayWindow = nil
        }
    }
    
    // MARK: - 定时器管理
    
    private func startTimer() {
        stopTimer()

        // 如果使用智能提醒模式，则不启动普通定时器
        if useSmartReminder {
            return
        }

        // 检查是否启用了提醒
        guard config.isEnabled else {
            return
        }

        // 如果没有上次提醒时间，设置当前时间为上次提醒时间
        if config.lastReminderTime == nil {
            config.lastReminderTime = Date()
            save()
        }

        // 计算从上次提醒到现在经过的时间
        let timeSinceLastReminder: TimeInterval
        if let lastTime = config.lastReminderTime {
            timeSinceLastReminder = Date().timeIntervalSince(lastTime)
        } else {
            timeSinceLastReminder = 0
        }

        // 检查应用退出时间，判断是否需要保持剩余时间
        if let appExitTime = loadAppExitTime() {
            let timeSinceExit = Date().timeIntervalSince(appExitTime)
            
            // 使用智能提醒的休息认定时间作为基准
            let timeKeepThreshold = smartConfig.restRecognitionTime
            
            // 如果应用关闭时间小于休息认定时间，则保持剩余时间
            if timeSinceExit < timeKeepThreshold {
                // 保持剩余时间，不重置
                print("✅ 应用关闭时间 \(Int(timeSinceExit))秒 < 阈值 \(Int(timeKeepThreshold))秒，保持剩余时间")
            } else {
                // 超过阈值，重置提醒时间
                print("⏱️ 应用关闭时间 \(Int(timeSinceExit))秒 >= 阈值 \(Int(timeKeepThreshold))秒，重置提醒时间")
                config.lastReminderTime = Date()
                save()
            }
        }

        // 计算到下次提醒的时间间隔
        let interval = TimeInterval(config.intervalMinutes * 60)
        let nextReminderDelay = max(1, interval - timeSinceLastReminder) // 至少延迟1秒

        // 创建定时器
        timer = Timer.scheduledTimer(
            withTimeInterval: nextReminderDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showReminder()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - 提醒显示
    
    private func showReminder() {
        guard !isShowingAlert else { return }
        isShowingAlert = true

        // 播放声音
        playSound()

        // 显示提醒蒙版窗口
        let window = ReminderOverlayWindow(message: config.message) { [weak self] in
            guard let self = self else { return }

            self.isShowingAlert = false
            self.overlayWindow = nil

            // 更新提醒时间，重启定时器
            self.updateLastReminderTime()
        }

        overlayWindow = window
        window.show()
    }
    
    /// 在指定秒数后提醒
    private func scheduleReminderIn(_ seconds: TimeInterval) {
        stopTimer()
        timer = Timer.scheduledTimer(
            withTimeInterval: seconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showReminder()
            }
        }
    }
    
    private func updateLastReminderTime() {
        config.lastReminderTime = Date()
        save()
        
        if config.isEnabled {
            startTimer()
        }
    }
    
    // MARK: - 声音播放
    
    private func playSound() {
        // 使用系统内置的声音
        let soundNames: [String: NSSound.Name] = [
            "Glass": .init("Glass"),
            "Purr": .init("Purr"),
            "Sosumi": .init("Sosumi"),
            "Pop": .init("Pop")
        ]
        
        if let soundName = soundNames[config.soundName],
           let sound = NSSound(named: soundName) {
            sound.play()
        } else if let sound = NSSound(named: .init("Glass")) {
            sound.play()
        }
    }
    
    // MARK: - 应用生命周期
    
    @objc private func applicationDidBecomeActive() {
        // 根据当前模式重新启动相应的提醒功能
        if useSmartReminder {
            if smartConfig.isEnabled && smartReminderManager == nil {
                startSmartReminderManager()
            }
        } else {
            if config.isEnabled && timer == nil {
                startTimer()
            }
        }
    }
    
    // MARK: - 测试方法
    
    /// 测试提醒（立即显示）
    func testReminder() {
        showReminder()
    }
    
    // MARK: - 倒计时
    
    /// 获取智能提醒的倒计时（秒），如果未启用或未运行返回 nil
    var nextSmartReminderCountdown: TimeInterval? {
        return smartReminderManager?.getNextCountdown()
    }

    /// 获取距离下次提醒的剩余时间（秒）
    var nextReminderCountdown: TimeInterval? {
        guard config.isEnabled else { return nil }
        
        // 如果使用智能提醒模式,不显示倒计时（智能模式有自己的倒计时）
        if useSmartReminder && smartConfig.isEnabled {
            return nil
        }
        
        let interval = TimeInterval(config.intervalMinutes * 60)
        
        if let lastTime = config.lastReminderTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            let remaining = interval - elapsed
            return max(0, remaining)
        } else {
            // 如果没有上次提醒时间,返回完整的间隔时间
            return interval
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let smartReminderNeedsPermission = Notification.Name("smartReminderNeedsPermission")
    static let smartReminderDidStart = Notification.Name("smartReminderDidStart")
}
