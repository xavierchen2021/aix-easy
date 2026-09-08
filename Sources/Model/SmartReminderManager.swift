import Cocoa

// MARK: - 状态枚举

/// 智能提醒内部状态
enum SmartReminderState {
    case working        // 键鼠活动中，工作计时累加
    case idle           // 键鼠停止，空闲时间累加
    case videoMode      // 无键鼠+有音频，工作计时暂停
    case away           // 空闲超过阈值，休息认定计时中
    case rested         // 离开时间达到休息认定，工作已重置，等待用户回来
    case overlay        // 工作倒计时归零，蒙版显示中，休息计时中
}

// MARK: - 智能提醒管理器

/// 基于键鼠活动的智能工作/休息提醒
///
/// 核心逻辑（严格按需求）：
/// 1. 键鼠活动 → 工作计时累加，空闲=0
/// 2. 键鼠停止 → 空闲累加，工作计时继续累加
/// 3. 键鼠恢复 → 空闲清零
/// 4. 空闲>6s + 10s内有5s音频响度 → 视频模式（空闲清零，工作暂停）
/// 5. 视频模式 + 键鼠连续活动≥15s → 退出视频（恢复工作计时）
/// 6. 空闲≥阈值 → 离开，工作计时暂停，开始休息认定计时
/// 7. 离开时间≥休息认定时间 → 工作计时重置
/// 8. 离开不足 + 键鼠恢复 → 延续之前工作计时
/// 9. 工作倒计时=0 → 弹蒙版 + 休息计时
/// 10. 休息计时达到休息时间 → 自动关闭蒙版，工作重置
/// 11. 用户点"稍后休息" → 关闭蒙版，工作重置
@MainActor
class SmartReminderManager {
    
    // MARK: - 依赖
    
    let inputMonitor: InputMonitor
    private let reminderOverlay: ReminderOverlayWindow
    let audioMonitor = AudioActivityMonitor.shared
    
    // MARK: - 状态
    
    var state: SmartReminderState = .working
    var workTime: TimeInterval = 0       // 累计工作时间（秒）
    var idleTime: TimeInterval = 0       // 当前连续空闲时间（秒）
    var restTime: TimeInterval = 0       // 蒙版显示后的休息计时（秒）
    var awayStartTime: Date?             // 进入离开状态的时间
    var videoActivityDuration: Int = 0   // 视频模式下连续键鼠活动秒数
    private var timer: Timer?
    
    // 音频检测状态（由 extension 使用）
    var audioCheckStartTime: Date?
    var audioLoudCount: Int = 0       // 检测窗口内响度达标的秒数
    var audioCheckCompleted: Bool = false  // 本轮空闲是否已完成检测
    
    // MARK: - 配置
    
    var config: SmartReminderConfig {
        didSet {
            if config.isEnabled != oldValue.isEnabled {
                config.isEnabled ? startMonitoring() : stopMonitoring()
                return
            }
            if config.idleThreshold != oldValue.idleThreshold {
                inputMonitor.updateIdleThreshold(config.idleThreshold)
            }
        }
    }
    
    // MARK: - 初始化
    
    init(config: SmartReminderConfig, reminderOverlay: ReminderOverlayWindow) {
        self.config = config
        self.reminderOverlay = reminderOverlay
        self.inputMonitor = InputMonitor(idleThreshold: config.idleThreshold)
        
        // 蒙版按钮回调：用户点击"稍后休息"
        reminderOverlay.onContinue = { [weak self] in
            guard let self = self else { return }
            self.dismissOverlay()
            self.resetWork()
            ReminderLogger.shared.logAction("用户点击稍后休息，工作计时重置")
        }
        
        // 锁屏/解锁
        inputMonitor.onLockStateChanged = { [weak self] locked in
            Task { @MainActor in self?.handleLockStateChanged(locked) }
        }
        
        // 系统唤醒
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSystemWake),
            name: .systemDidWake, object: nil
        )
    }
    
    // MARK: - 启动 / 停止
    
    func start() {
        guard config.isEnabled else { return }
        ReminderLogger.shared.logInfo("🚀 启动智能提醒 - 工作:\(config.workDuration/60)分 休息:\(config.restDuration/60)分")
        
        restoreState()
        startMonitoring()
        
        NotificationCenter.default.post(name: .init("SmartReminderEnabled"), object: nil)
    }
    
    func stop() {
        stopMonitoring()
        dismissOverlay()
        resetWork()
        
        NotificationCenter.default.post(name: .init("SmartReminderDisabled"), object: nil)
    }
    
    func reset() { resetWork() }
    
    private func startMonitoring() {
        inputMonitor.updateIdleThreshold(config.idleThreshold)
        inputMonitor.startMonitoring()
        startTimer()
    }
    
    private func stopMonitoring() {
        inputMonitor.stopMonitoring()
        stopTimer()
    }
    
    // MARK: - 定时器
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - 核心 Tick（每秒执行一次）
    
    private func tick() {
        let sinceLastActivity = inputMonitor.timeSinceLastActivity()
        let isActive = sinceLastActivity < 1.0
        
        switch state {
            
        // ─── 工作中 ───
        case .working:
            if isActive {
                workTime += 1
                idleTime = 0
                resetAudioCheck()
                
                if workTime >= config.workDuration {
                    showOverlay()
                }
            } else {
                idleTime += 1
                workTime += 1  // idle 状态下工作计时继续
                state = .idle
                
                if workTime >= config.workDuration {
                    showOverlay()
                }
            }
            
        // ─── 空闲中（工作计时继续累加） ───
        case .idle:
            if isActive {
                idleTime = 0
                state = .working
                resetAudioCheck()
            } else {
                idleTime += 1
                workTime += 1  // idle 状态下工作计时继续
                
                // 空闲 > 6s → 启动音频检测（本轮空闲仅检测一次）
                if idleTime > 6 && !audioCheckCompleted {
                    checkAudioAndEnterVideoMode()
                    if state == .videoMode { break }
                }
                
                // 空闲 ≥ 阈值 → 进入离开状态（工作计时暂停）
                if idleTime >= config.idleThreshold {
                    state = .away
                    awayStartTime = Date()
                    resetAudioCheck()
                    ReminderLogger.shared.logInfo("⏹️ 空闲≥\(config.idleThreshold)s，进入离开状态")
                }
                
                // idle 期间工作时长达标也弹蒙版
                if workTime >= config.workDuration {
                    showOverlay()
                }
            }
            
        // ─── 视频模式 ───
        case .videoMode:
            if isActive {
                videoActivityDuration += 1
                if videoActivityDuration >= 15 {
                    // 连续活动 15 秒以上，认定为恢复工作
                    idleTime = 0
                    videoActivityDuration = 0
                    state = .working
                    resetAudioCheck()
                    ReminderLogger.shared.logInfo("🎥 键鼠持续活动≥15秒，退出视频模式")
                }
                // 不足 6 秒，保持视频模式
            } else {
                // 活动中断，重置计数器
                videoActivityDuration = 0
            }
            // 视频模式：不累加 workTime，不累加 idleTime
            
        // ─── 离开中（休息认定计时中） ───
        case .away:
            if isActive {
                // 休息不足，延续之前的工作计时
                idleTime = 0
                state = .working
                awayStartTime = nil
                resetAudioCheck()
                ReminderLogger.shared.logInfo("👤 键鼠恢复，休息不足，延续工作计时")
            } else {
                // 检查休息认定
                if let start = awayStartTime,
                   Date().timeIntervalSince(start) >= config.restRecognitionTime {
                    workTime = 0
                    state = .rested
                    ReminderLogger.shared.logEvent("✅ 休息认定达标，工作计时已重置")
                }
            }
            
        // ─── 已休息（等待用户回来） ───
        case .rested:
            if isActive {
                idleTime = 0
                state = .working
                awayStartTime = nil
                resetAudioCheck()
                ReminderLogger.shared.logEvent("✅ 键鼠恢复，开始新的工作周期")
            }
            
        // ─── 蒙版显示中（休息计时） ───
        case .overlay:
            restTime += 1
            
            // 更新蒙版显示
            let remaining = max(0, config.restDuration - restTime)
            let m = Int(remaining) / 60
            let s = Int(remaining) % 60
            let timeStr = String(format: "%02d:%02d", m, s)
            reminderOverlay.remainingTime = timeStr
            reminderOverlay.message = config.reminderMessage
            
            // 休息时间到 → 自动关闭蒙版
            if restTime >= config.restDuration {
                dismissOverlay()
                resetWork()
                ReminderLogger.shared.logEvent("✅ 休息时间到，自动关闭蒙版，工作计时重置")
            }
        }
        
        updateStatusBar()
    }
    
    // MARK: - 蒙版操作
    
    private func showOverlay() {
        state = .overlay
        restTime = 0
        
        let m = Int(config.restDuration) / 60
        let s = Int(config.restDuration) % 60
        reminderOverlay.message = config.reminderMessage
        reminderOverlay.remainingTime = String(format: "%02d:%02d", m, s)
        reminderOverlay.show()
        
        playSound(config.soundName)
        ReminderLogger.shared.logEvent("⏰ 工作\(config.workDuration/60)分钟达标，弹出蒙版")
    }
    
    func dismissOverlay() {
        if reminderOverlay.isVisible {
            reminderOverlay.close()
        }
    }
    
    // MARK: - 重置
    
    func resetWork() {
        state = .working
        workTime = 0
        idleTime = 0
        restTime = 0
        awayStartTime = nil
        videoActivityDuration = 0
        resetAudioCheck()
        inputMonitor.refreshActivity()
    }
    
    // MARK: - 状态栏更新
    
    private func updateStatusBar() {
        let userInfo: [String: Any] = [
            "isResting": state == .overlay,
            "activeDuration": min(workTime, config.workDuration),
            "idleTime": idleTime,
            "workDuration": config.workDuration,
            "restDuration": config.restDuration,
            "restStartTime": (state == .overlay ? Date().addingTimeInterval(-restTime) : nil) as Any,
            "hasPermission": InputMonitor.hasAccessibilityPermission()
        ]
        NotificationCenter.default.post(name: .init("SmartReminderStateChanged"), object: nil, userInfo: userInfo)
    }
}
