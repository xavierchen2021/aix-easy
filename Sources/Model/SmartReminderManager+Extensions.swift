import Cocoa

// MARK: - 音频检测

@MainActor
extension SmartReminderManager {
    
    /// 检测音频并决定是否进入视频模式（一次性10秒窗口）
    func checkAudioAndEnterVideoMode() {
        // 首次进入：启动音频监控，设置检测起始时间
        if audioCheckStartTime == nil {
            audioCheckStartTime = Date()
            audioLoudCount = 0
            audioMonitor.startMonitoring()
            return
        }
        
        guard let start = audioCheckStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        
        // 10秒检测窗口期内：每秒统计是否有足够响度的音频
        if elapsed <= 10.0 {
            if audioMonitor.hasAudioSamples() && audioMonitor.isOutputLoud() {
                audioLoudCount += 1
            }
            return
        }
        
        // 10秒窗口结束，做最终判定：至少5秒有响度达标的音频
        if audioLoudCount >= 5 {
            idleTime = 0
            state = .videoMode
            ReminderLogger.shared.logInfo("🎥 进入视频模式（\(audioLoudCount)/10秒有音频），工作计时暂停")
            resetAudioCheck()
        } else {
            // 检测未达标，停止监控，本轮空闲不再重试
            ReminderLogger.shared.logInfo("🎧 音频检测未达标（\(audioLoudCount)/10秒），停止监听")
            audioCheckStartTime = nil
            audioLoudCount = 0
            audioCheckCompleted = true
            audioMonitor.stopMonitoring()
        }
    }
    
    func resetAudioCheck() {
        audioCheckStartTime = nil
        audioLoudCount = 0
        audioCheckCompleted = false
        audioMonitor.stopMonitoring()
    }
}

// MARK: - 锁屏 / 系统唤醒

@MainActor
extension SmartReminderManager {
    
    func handleLockStateChanged(_ locked: Bool) {
        if locked {
            if state == .working || state == .idle {
                state = .away
                awayStartTime = Date()
                ReminderLogger.shared.logInfo("🔒 锁屏，进入离开状态")
            }
        } else {
            if let start = awayStartTime {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= config.restRecognitionTime {
                    resetWork()
                    playSound(config.restEndSoundName)
                    ReminderLogger.shared.logEvent("✅ 锁屏休息充足(\(Int(elapsed))秒)")
                } else {
                    state = .working
                    idleTime = 0
                    awayStartTime = nil
                }
            }
            inputMonitor.refreshActivity()
        }
    }
    
    @objc func handleSystemWake() {
        guard config.isEnabled else { return }
        ReminderLogger.shared.logInfo("🌅 系统唤醒")
        
        if state == .overlay {
            dismissOverlay()
            resetWork()
            return
        }
        
        if let start = awayStartTime,
           Date().timeIntervalSince(start) >= config.restRecognitionTime {
            resetWork()
            ReminderLogger.shared.logEvent("🌅 唤醒后休息充足，重置")
        } else {
            state = .working
            idleTime = 0
            inputMonitor.refreshActivity()
        }
    }
}

// MARK: - 持久化 & 辅助

@MainActor
extension SmartReminderManager {
    
    func saveState() {
        let dict: [String: Any] = [
            "workTime": workTime,
            "awayStartTime": awayStartTime?.timeIntervalSince1970 ?? 0
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            try? AppDatabase.shared.settingsStore.saveConfig(key: "smartReminderState", value: str)
        }
    }
    
    func restoreState() {
        guard let str = AppDatabase.shared.settingsStore.loadConfig(key: "smartReminderState"),
              let data = str.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        workTime = dict["workTime"] as? TimeInterval ?? 0
        
        if let ts = dict["awayStartTime"] as? TimeInterval, ts > 0 {
            let start = Date(timeIntervalSince1970: ts)
            if Date().timeIntervalSince(start) >= config.restRecognitionTime {
                workTime = 0
                state = .working
            } else {
                awayStartTime = start
                state = .away
            }
        }
    }
    
    func getNextCountdown() -> TimeInterval? {
        if state == .overlay {
            return max(0, config.restDuration - restTime)
        }
        return max(0, config.workDuration - workTime)
    }
    
    func playSound(_ soundName: String) {
        let names: [String: NSSound.Name] = [
            "Glass": .init("Glass"), "Purr": .init("Purr"),
            "Sosumi": .init("Sosumi"), "Pop": .init("Pop"),
            "Basso": .init("Basso"), "Blow": .init("Blow"),
            "Bottle": .init("Bottle"), "Frog": .init("Frog"),
            "Funk": .init("Funk"), "Hero": .init("Hero"),
            "Morse": .init("Morse"), "Ping": .init("Ping"),
            "Submarine": .init("Submarine"), "Tink": .init("Tink")
        ]
        if let n = names[soundName], let s = NSSound(named: n) {
            s.play()
        } else if let s = NSSound(named: .init("Glass")) {
            s.play()
        }
    }
}
