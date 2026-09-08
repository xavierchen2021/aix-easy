import Cocoa

/// 智能提醒状态
private enum ReminderState {
    case working        // 有键鼠活动，工作计时中
    case idle           // 无键鼠活动，空闲累加中
    case videoMode      // 无键鼠+有音频，暂停工作计时
    case away           // 空闲超过阈值，等待休息认定
    case restRecognized // 离开时长超过休息认定时间，等待用户回来
    case overlay        // 工作倒计时归零，蒙版显示中
}

/// 智能提醒管理器（重构版）
/// 基于用户键鼠活动智能提醒休息
@MainActor
class SmartReminderManager {
    
    // MARK: - Properties
    
    private let inputMonitor: InputMonitor
    private let reminderOverlay: ReminderOverlayWindow
    private let audioMonitor = AudioActivityMonitor.shared
    
    private var state: ReminderState = .working
    private var workTime: TimeInterval = 0       // 累计工作时间（秒）
    private var idleTime: TimeInterval = 0       // 当前连续空闲时间（秒）
    private var restTime: TimeInterval = 0       // 蒙版显示后的休息计时（秒）
    private var awayStartTime: Date?             // 进入 away 状态的时间
    private var timer: Timer?
    
    // 音频检测
    private var audioCheckStartTime: Date?
    private var audioWindowAllActive: Bool = true
    
    // 配置
    var config: SmartReminderConfig {
        didSet {
            if config.isEnabled != oldValue.isEnabled {
                if config.isEnabled {
                    inputMonitor.updateIdleThreshold(config.idleThreshold)
                    inputMonitor.startMonitoring()
                    startTimer()
                } else {
                    inputMonitor.stopMonitoring()
                    stopTimer()
                }
                return
            }
            if config.idleThreshold != oldValue.idleThreshold {
                inputMonitor.updateIdleThreshold(config.idleThreshold)
            }
        }
    }
    
    // MARK: - Initialization
    
    init(config: SmartReminderConfig, reminderOverlay: ReminderOverlayWindow) {
        self.config = config
        self.reminderOverlay = reminderOverlay
        self.inputMonitor = InputMonitor(idleThreshold: config.idleThreshold)
        
        setupOverlayCallback()
        
        // 监听系统唤醒
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: .systemDidWake,
            object: nil
        )
        
        // 监听锁屏/解锁
        inputMonitor.onLockStateChanged = { [weak self] locked in
            Task { @MainActor in
                self?.handleLockStateChanged(locked)
            }
        }
    }
    
    // MARK: - Public Methods
    
    func start() {
        guard config.isEnabled else { return }
        
        print("🚀 启动智能提醒管理器")
        ReminderLogger.shared.logInfo("启动智能提醒 - 工作:\(config.workDuration/60)分 休息:\(config.restDuration/60)分 空闲阈值:\(config.idleThreshold)秒")
        
        restoreState()
        inputMonitor.startMonitoring()
        startTimer()
        updateStatusBar()
        
        NotificationCenter.default.post(name: NSNotification.Name("SmartReminderEnabled"), object: nil)
    }
    
    func stop() {
        print("⏹️ 停止智能提醒管理器")
        inputMonitor.stopMonitoring()
        stopTimer()
        closeOverlay()
        resetAll()
        
        NotificationCenter.default.post(name: NSNotification.Name("SmartReminderDisabled"), object: nil)
    }
    
    func reset() {
        resetAll()
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Core Tick
    
    private func tick() {
        let sinceLastActivity = inputMonitor.timeSinceLastActivity()
        let isActive = sinceLastActivity < 1.0
        
        switch state {
        case .working:
            if isActive {
                workTime += 1
                idleTime = 0
                resetAudioCheck()
                
                // 检查是否达到工作时长
                if workTime >= config.workDuration {
                    showOverlay()
                }
            } else {
                idleTime += 1
                state = .idle
                ReminderLogger.shared.logInfo("⏹️ 用户停止操作，进入空闲")
            }
            
        case .idle:
            if isActive {
                // 键鼠恢复，空闲清零，继续工作
                idleTime = 0
                state = .working
                resetAudioCheck()
            } else {
                idleTime += 1
                
                // 空闲≥20s，启动音频检测
                if idleTime >= 20 {
                    if audioCheckStartTime == nil {
                        startAudioCheck()
                    }
                    evaluateAudioCheck()
                    
                    // 如果音频检测认定为视频模式，state 会在 evaluateAudioCheck 中改变
                    if state == .videoMode { return }
                }
                
                // 空闲≥阈值，进入离开状态
                if idleTime >= config.idleThreshold {
                    state = .away
                    awayStartTime = Date()
                    ReminderLogger.shared.logInfo("⏹️ 空闲超过阈值，进入离开状态")
                }
            }
            
        case .videoMode:
            if isActive {
                // 键鼠恢复，退出视频模式，继续工作计时
                idleTime = 0
                state = .working
                resetAudioCheck()
                audioMonitor.stopMonitoring()
                ReminderLogger.shared.logInfo("🎥 退出视频模式，恢复工作计时")
            }
            // 视频模式下不累加 workTime，也不累加 idleTime
            
        case .away:
            if isActive {
                // 用户回来了，休息不足，延续之前的工作计时
                idleTime = 0
                state = .working
                awayStartTime = nil
                resetAudioCheck()
                ReminderLogger.shared.logInfo("👤 用户回来（休息不足），延续工作计时")
            } else {
                // 检查是否达到休息认定时间
                if let start = awayStartTime {
                    let awayDuration = Date().timeIntervalSince(start)
                    if awayDuration >= config.restRecognitionTime {
                        state = .restRecognized
                        workTime = 0
                        ReminderLogger.shared.logEvent("✅ 休息认定达标，工作计时已重置")
                    }
                }
            }
            
        case .restRecognized:
            if isActive {
                // 用户回来了，工作计时已重置，开始新周期
                idleTime = 0
                state = .working
                awayStartTime = nil
                resetAudioCheck()
                ReminderLogger.shared.logEvent("✅ 用户回来，开始新工作周期")
            }
            
        case .overlay:
            restTime += 1
            
            // 更新蒙版倒计时
            let remaining = max(0, config.restDuration - restTime)
            let m = Int(remaining) / 60
            let s = Int(remaining) % 60
            reminderOverlay.remainingTime = String(format: "%02d:%02d", m, s)
            reminderOverlay.message = "休息中... 剩余 \(String(format: "%02d:%02d", m, s))"
            
            // 休息时间到，自动关闭蒙版
            if restTime >= config.restDuration {
                closeOverlay()
                resetAll()
                ReminderLogger.shared.logEvent("✅ 休息时间到，自动关闭蒙版")
            }
        }
        
        updateStatusBar()
    }
    
    // MARK: - Overlay
    
    private func showOverlay() {
        state = .overlay
        restTime = 0
        
        reminderOverlay.message = config.reminderMessage
        reminderOverlay.remainingTime = String(format: "%02d:%02d", Int(config.restDuration) / 60, Int(config.restDuration) % 60)
        reminderOverlay.show()
        
        playSound(config.soundName)
        
        ReminderLogger.shared.logEvent("⏰ 工作时间达到\(config.workDuration/60)分钟，显示蒙版")
    }
    
    private func closeOverlay() {
        if reminderOverlay.isVisible {
            reminderOverlay.close()
        }
    }
    
    private func setupOverlayCallback() {
        Task { @MainActor in
            self.reminderOverlay.onContinue = { [weak self] in
                guard let self = self else { return }
                // 用户点击"稍后休息"
                self.closeOverlay()
                self.resetAll()
                ReminderLogger.shared.logAction("用户点击稍后休息")
            }
        }
    }
    
    // MARK: - Audio Detection
    
    private func startAudioCheck() {
        audioCheckStartTime = Date()
        audioWindowAllActive = true
        audioMonitor.startMonitoring()
    }
    
    private func resetAudioCheck() {
        audioCheckStartTime = nil
        audioWindowAllActive = true
        audioMonitor.stopMonitoring()
    }
    
    private func evaluateAudioCheck() {
        guard let start = audioCheckStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(start)
        
        if elapsed <= 5.0 {
            if !audioMonitor.hasAudioSamples() {
                if elapsed >= 1.0 {
                    audioWindowAllActive = false
                    audioMonitor.stopMonitoring()
                }
                return
            }
            
            let isLoud = audioMonitor.isOutputLoud()
            if audioWindowAllActive && !isLoud {
                audioWindowAllActive = false
                audioMonitor.stopMonitoring()
            }
        }
        
        if elapsed >= 5.0 {
            if audioWindowAllActive {
                // 连续5秒有音频 → 视频模式
                state = .videoMode
                resetAudioCheck()
                ReminderLogger.shared.logInfo("🎥 进入视频模式，暂停工作计时")
            }
            audioCheckStartTime = nil
            audioMonitor.stopMonitoring()
        }
    }
    
    // MARK: - Lock/Wake
    
    private func handleLockStateChanged(_ locked: Bool) {
        if locked {
            // 锁屏 → 视为离开
            if state == .working || state == .idle {
                state = .away
                awayStartTime = Date()
            }
        } else {
            // 解锁 → 检查离开时长
            if let start = awayStartTime {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= config.restRecognitionTime {
                    // 休息充足
                    workTime = 0
                    state = .working
                    idleTime = 0
                    awayStartTime = nil
                    playSound(config.restEndSoundName)
                    ReminderLogger.shared.logEvent("✅ 锁屏休息充足(\(Int(elapsed))秒)，重置工作计时")
                } else {
                    // 休息不足，延续工作
                    state = .working
                    idleTime = 0
                    awayStartTime = nil
                }
            }
            inputMonitor.refreshActivity()
        }
    }
    
    @objc private func handleSystemWake() {
        guard config.isEnabled else { return }
        ReminderLogger.shared.logInfo("🌅 系统唤醒")
        
        // 如果蒙版显示中，关闭蒙版重置
        if state == .overlay {
            closeOverlay()
            resetAll()
            return
        }
        
        // 检查离开时长
        if let start = awayStartTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= config.restRecognitionTime {
                workTime = 0
                ReminderLogger.shared.logEvent("🌅 唤醒后休息充足，重置工作计时")
            }
        }
        
        state = .working
        idleTime = 0
        inputMonitor.refreshActivity()
        
        // 重启定时器
        stopTimer()
        startTimer()
    }
    
    // MARK: - Helpers
    
    private func resetAll() {
        state = .working
        workTime = 0
        idleTime = 0
        restTime = 0
        awayStartTime = nil
        resetAudioCheck()
        inputMonitor.refreshActivity()
    }
    
    private func updateStatusBar() {
        let displayWorkTime = min(workTime, config.workDuration)
        
        let userInfo: [String: Any] = [
            "isResting": state == .overlay,
            "activeDuration": displayWorkTime,
            "idleTime": idleTime,
            "workDuration": config.workDuration,
            "restDuration": config.restDuration,
            "restStartTime": (state == .overlay ? Date().addingTimeInterval(-restTime) : nil) as Any,
            "hasPermission": InputMonitor.hasAccessibilityPermission()
        ]
        NotificationCenter.default.post(name: NSNotification.Name("SmartReminderStateChanged"), object: nil, userInfo: userInfo)
    }
    
    private func playSound(_ soundName: String) {
        let soundNames: [String: NSSound.Name] = [
            "Glass": .init("Glass"),
            "Purr": .init("Purr"),
            "Sosumi": .init("Sosumi"),
            "Pop": .init("Pop"),
            "Basso": .init("Basso"),
            "Blow": .init("Blow"),
            "Bottle": .init("Bottle"),
            "Frog": .init("Frog"),
            "Funk": .init("Funk"),
            "Hero": .init("Hero"),
            "Morse": .init("Morse"),
            "Ping": .init("Ping"),
            "Submarine": .init("Submarine"),
            "Tink": .init("Tink")
        ]
        
        if let name = soundNames[soundName], let sound = NSSound(named: name) {
            sound.play()
        } else if let sound = NSSound(named: .init("Glass")) {
            sound.play()
        }
    }
    
    // MARK: - Public Queries
    
    func getNextCountdown() -> TimeInterval? {
        if state == .overlay {
            return max(0, config.restDuration - restTime)
        }
        return max(0, config.workDuration - workTime)
    }
    
    // MARK: - State Persistence
    
    func saveState() {
        let stateDict: [String: Any] = [
            "workTime": workTime,
            "state": stateString(),
            "awayStartTime": awayStartTime?.timeIntervalSince1970 ?? 0
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: stateDict),
           let str = String(data: data, encoding: .utf8) {
            try? AppDatabase.shared.settingsStore.saveConfig(key: "smartReminderState", value: str)
        }
    }
    
    func restoreState() {
        guard let str = AppDatabase.shared.settingsStore.loadConfig(key: "smartReminderState"),
              let data = str.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        workTime = dict["workTime"] as? TimeInterval ?? 0
        
        if let awayTs = dict["awayStartTime"] as? TimeInterval, awayTs > 0 {
            let awayStart = Date(timeIntervalSince1970: awayTs)
            let elapsed = Date().timeIntervalSince(awayStart)
            
            if elapsed >= config.restRecognitionTime {
                // 离开时间足够长，视为已休息
                workTime = 0
                state = .working
                print("✅ 恢复状态: 离开时间充足，重置工作计时")
            } else {
                awayStartTime = awayStart
                state = .away
                print("✅ 恢复状态: 离开中，workTime=\(workTime)")
            }
        } else {
            state = .working
            print("✅ 恢复状态: workTime=\(workTime)")
        }
    }
    
    private func stateString() -> String {
        switch state {
        case .working: return "working"
        case .idle: return "idle"
        case .videoMode: return "videoMode"
        case .away: return "away"
        case .restRecognized: return "restRecognized"
        case .overlay: return "overlay"
        }
    }
}
