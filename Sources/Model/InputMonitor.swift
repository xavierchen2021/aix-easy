import Cocoa
import ApplicationServices

/// 输入事件监听器
/// 使用 CGEventTap 监听键盘和鼠标事件
final class InputMonitor: @unchecked Sendable {

    /// 检查是否已获得辅助功能（Accessibility）权限
    static func hasAccessibilityPermission() -> Bool {
        // 使用 AXIsProcessTrustedWithOptions(nil) 是检查权限最准确的方式，避免缓存问题
        return AXIsProcessTrustedWithOptions(nil)
    }

    /// 弹出系统设置页面以请求辅助功能权限（会打开系统偏好设置）
    @MainActor static func promptForAccessibilityPermission() {
        // Open System Settings Accessibility pane — this avoids touching the AX constant directly and works reliably.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }    
    // MARK: - Properties
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastActivityTime: Date = Date()
    private var idleThreshold: TimeInterval = 60.0 // 空闲阈值（秒）
    private var isLocked: Bool = false
    private var lockObserver: Any?
    private var unlockObserver: Any?
    private var screenSleepObserver: Any?
    private var screenWakeObserver: Any?
    
    // 回调闭包
    var onActivityDetected: (@Sendable () -> Void)?
    var onLockStateChanged: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init(idleThreshold: TimeInterval = 60.0) {
        self.idleThreshold = idleThreshold
    }

    /// 更新空闲阈值（秒），并限制在 60..180 秒
    func updateIdleThreshold(_ threshold: TimeInterval) {
        let clamped = max(60.0, min(threshold, 180.0))
        self.idleThreshold = clamped
    }
    
    // MARK: - Public Methods
    
    /// 开始监听输入事件
    func startMonitoring() {
        // 监听系统屏幕睡眠/唤醒与锁屏/解锁事件
        // Remove any existing observers first to avoid duplicates
        stopMonitoringObservers()

        let nc = NSWorkspace.shared.notificationCenter

        screenSleepObserver = nc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            guard !self.isLocked else { return } // 防止重复触发
            self.isLocked = true
            self.onLockStateChanged?(true)
            self.lastActivityTime = Date()
        }

        screenWakeObserver = nc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            guard self.isLocked else { return } // 防止重复触发
            self.isLocked = false
            self.onLockStateChanged?(false)
            self.lastActivityTime = Date()
            // 发送系统唤醒通知
            NotificationCenter.default.post(name: .systemDidWake, object: nil)
        }

        // Distributed notifications for screen lock/unlock
        let dnc = DistributedNotificationCenter.default()
        lockObserver = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            guard !self.isLocked else { return } // 防止重复触发
            self.isLocked = true
            self.onLockStateChanged?(true)
            self.lastActivityTime = Date()
        }

        unlockObserver = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            guard self.isLocked else { return } // 防止重复触发
            self.isLocked = false
            self.onLockStateChanged?(false)
            self.lastActivityTime = Date()
        }

        // 检查是否有辅助功能权限以创建事件监听器
        if !InputMonitor.hasAccessibilityPermission() {
            print("⚠️ 未授予辅助功能权限，无法监听键盘/鼠标等输入事件")
        } else {
            // 创建事件监听器
            let eventMask = (1 << CGEventType.keyDown.rawValue) |
                            (1 << CGEventType.mouseMoved.rawValue) |
                            (1 << CGEventType.leftMouseDragged.rawValue) |
                            (1 << CGEventType.rightMouseDragged.rawValue) |
                            (1 << CGEventType.scrollWheel.rawValue)
            
            eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { proxy, type, event, refcon in
                    return InputMonitor.eventCallback(
                        proxy: proxy,
                        type: type,
                        event: event,
                        refcon: refcon
                    )
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            
            if let eventTap = eventTap {
                // 创建运行循环源
                runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

                // 添加到运行循环
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

                // 启用事件监听
                CGEvent.tapEnable(tap: eventTap, enable: true)
            } else {
                print("⚠️ 无法创建 CGEventTap，可能需要辅助功能权限")
            }
        }

        print("✅ 输入事件监听已启动")
    }
    
    private func stopMonitoringObservers() {
        if let lockObserver = lockObserver {
            DistributedNotificationCenter.default().removeObserver(lockObserver)
            self.lockObserver = nil
        }
        if let unlockObserver = unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
            self.unlockObserver = nil
        }
        if let screenSleepObserver = screenSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(screenSleepObserver)
            self.screenSleepObserver = nil
        }
        if let screenWakeObserver = screenWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(screenWakeObserver)
            self.screenWakeObserver = nil
        }
    }

    /// 停止监听输入事件
    func stopMonitoring() {
        stopMonitoringObservers()

        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.eventTap = nil
            self.runLoopSource = nil
            print("⏹️ 输入事件监听已停止")
        }
    }
    
    /// 刷新最后活动时间（手动标记为活跃）
    func refreshActivity() {
        lastActivityTime = Date()
        isLocked = false
    }
    
    /// 检查距离上次活动的时间
    func timeSinceLastActivity() -> TimeInterval {
        return Date().timeIntervalSince(lastActivityTime)
    }
    
    /// 检查当前是否空闲
    func isIdle() -> Bool {
        return isLocked || timeSinceLastActivity() > idleThreshold
    }
    
    // MARK: - Private Methods
    
    /// 事件回调函数
    private static func eventCallback(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        
        guard let refcon = refcon else {
            return Unmanaged.passUnretained(event)
        }
        
        // 获取 InputMonitor 实例
        let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
        
        // 处理 CGEventTap 被系统超时禁用的情况
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }
        
        // 更新最后活动时间
        monitor.lastActivityTime = Date()
        
        // 触发活动检测回调
        let callback = monitor.onActivityDetected
        DispatchQueue.main.async {
            callback?()
        }
        
        // 返回事件，让系统正常处理
        return Unmanaged.passUnretained(event)
    }
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let systemDidWake = Notification.Name("systemDidWake")
}
