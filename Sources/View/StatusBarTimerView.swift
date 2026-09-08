import Cocoa

/// 菜单栏倒计时显示视图
class StatusBarTimerView: NSView {
    
    private let iconView = NSImageView()
    private let textStackView = NSStackView()
    private let topLabel = NSTextField()
    private let bottomLabel = NSTextField()
    
    // 方案1修改：移除内部定时器，完全依赖通知更新
    private var hasPermission: Bool = true // 增加：权限状态
    
    // 倒计时相关属性
    private var workDuration: TimeInterval = 2700 // 45分钟
    private var restDuration: TimeInterval = 300 // 5分钟
    private var activeDuration: TimeInterval = 0
    private var idleTime: TimeInterval = 0  // 新增：空闲时间
    private var restStartTime: Date?
    private var isResting: Bool = false
    
    /// 布局常量
    private let iconSize: CGFloat = 16
    private let doubleFontSize: CGFloat = 9
    private let spacing: CGFloat = 3
    private let padding: CGFloat = 2
    private let barHeight: CGFloat = 22
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // 设置图标
        iconView.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "AIX")
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        
        // 配置文本标签属性的辅助方法
        func configureLabel(_ label: NSTextField) {
            label.backgroundColor = NSColor.clear
            label.isBordered = false
            label.isEditable = false
            label.isSelectable = false
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.lineBreakMode = .byClipping
        }
        
        configureLabel(topLabel)
        configureLabel(bottomLabel)
        
        // 配置双行上下 StackView
        textStackView.orientation = .vertical
        textStackView.alignment = .leading
        textStackView.distribution = .fillProportionally
        textStackView.spacing = -1
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.addArrangedSubview(topLabel)
        textStackView.addArrangedSubview(bottomLabel)
        addSubview(textStackView)
        
        // 使用 Auto Layout
        NSLayoutConstraint.activate([
            // 图标约束
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            
            // 双行 StackView 约束（与图标和右边缘完全贴合紧凑）
            textStackView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: spacing),
            textStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            textStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // 视图整体高度
            heightAnchor.constraint(equalToConstant: barHeight)
        ])
        
        // 初始显示
        showTwoLineTimers(topText: "00:00", bottomText: "00:00")
        
        // 监听提醒相关通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSmartReminderStateChanged(_:)),
            name: NSNotification.Name("SmartReminderStateChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSmartReminderDisabled),
            name: NSNotification.Name("SmartReminderDisabled"),
            object: nil
        )
        
        // 监听系统唤醒通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: .systemDidWake,
            object: nil
        )
    }
    
    /// 显示上下双行状态/时间
    /// - Parameters:
    ///   - topText: 上层（次级色，如空闲时间或状态标题）
    ///   - bottomText: 下层（主色高亮，如倒计时或状态内容）
    private func showTwoLineTimers(topText: String, bottomText: String) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: doubleFontSize, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        
        topLabel.attributedStringValue = NSAttributedString(string: topText, attributes: [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ])
        
        bottomLabel.attributedStringValue = NSAttributedString(string: bottomText, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ])
    }
    
    /// 更新工作倒计时
    /// - Parameters:
    ///   - active: 当前活动时长（秒）
    ///   - work: 工作总时长（秒）
    ///   - idle: 空闲时间（秒）
    func updateWorkTimer(active: TimeInterval, work: TimeInterval, idle: TimeInterval) {
        isResting = false
        activeDuration = active
        workDuration = work
        idleTime = idle
        restStartTime = nil
        
        let remaining = max(0, work - active)
        if remaining <= 0 && active >= work {
            showTwoLineTimers(topText: L10n.tr("timer.workDoneTop"), bottomText: L10n.tr("timer.workDoneBottom"))
            return
        }
        
        let idleMin = Int(idle) / 60
        let idleSec = Int(idle) % 60
        
        let remainingMin = Int(remaining) / 60
        let remainingSec = Int(remaining) % 60
        
        let topText = String(format: "%02d:%02d", idleMin, idleSec)
        let bottomText = String(format: "%02d:%02d", remainingMin, remainingSec)
        
        showTwoLineTimers(topText: topText, bottomText: bottomText)
    }
    
    /// 更新休息倒计时
    /// - Parameters:
    ///   - rest: 休息总时长（秒）
    ///   - startTime: 休息开始时间
    func updateRestTimer(rest: TimeInterval, startTime: Date) {
        isResting = true
        restDuration = rest
        restStartTime = startTime
        activeDuration = 0
        
        // 方案1修改：不再启动内部定时器，完全依赖通知更新
        // Timer更新改由 SmartReminderManager 通过通知驱动
        updateDisplay()
    }
    
    /// 禁用菜单栏倒计时显示
    func disableTimer() {
        isResting = false
        restStartTime = nil
        activeDuration = 0
        idleTime = 0
        showTwoLineTimers(topText: L10n.tr("timer.closedTop"), bottomText: L10n.tr("timer.closedBottom"))
    }
    
    /// 更新显示内容
    /// 方案1修改：此方法现在完全由通知驱动，每次接收通知时调用
    private func updateDisplay() {
        if !hasPermission {
            showTwoLineTimers(topText: L10n.tr("timer.unauthorizedTop"), bottomText: L10n.tr("timer.unauthorizedBottom"))
            return
        }
        
        if isResting, let startTime = restStartTime {
            // 显示休息倒计时（上层「休息」，下层「05:00」）
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, restDuration - elapsed)
            
            let min = Int(remaining) / 60
            let sec = Int(remaining) % 60
            let countdownText = String(format: "%02d:%02d", min, sec)
            showTwoLineTimers(topText: L10n.tr("timer.restTop"), bottomText: countdownText)
        } else {
            // 显示工作倒计时，上层显示空闲时间，下层显示剩余时间
            let remaining = max(0, workDuration - activeDuration)
            if remaining <= 0 && activeDuration >= workDuration {
                showTwoLineTimers(topText: L10n.tr("timer.workDoneTop"), bottomText: L10n.tr("timer.workDoneBottom"))
                return
            }
            
            let idleMin = Int(idleTime) / 60
            let idleSec = Int(idleTime) % 60
            
            let remainingMin = Int(remaining) / 60
            let remainingSec = Int(remaining) % 60
            
            let topText = String(format: "%02d:%02d", idleMin, idleSec)
            let bottomText = String(format: "%02d:%02d", remainingMin, remainingSec)
            
            showTwoLineTimers(topText: topText, bottomText: bottomText)
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func onSmartReminderStateChanged(_ notification: Notification) {
        // 接收来自 SmartReminderManager 的状态更新
        // 方案1修改：每次接收通知都直接更新显示，不依赖内部 Timer
        if let userInfo = notification.userInfo {
            if let isRest = userInfo["isResting"] as? Bool,
               let active = userInfo["activeDuration"] as? TimeInterval,
               let work = userInfo["workDuration"] as? TimeInterval,
               let idle = userInfo["idleTime"] as? TimeInterval {  // 新增：接收空闲时间
                
                self.hasPermission = userInfo["hasPermission"] as? Bool ?? true
                
                if !hasPermission {
                    showTwoLineTimers(topText: L10n.tr("timer.unauthorizedTop"), bottomText: L10n.tr("timer.unauthorizedBottom"))
                    return
                }

                if isRest {
                    let rest = userInfo["restDuration"] as? TimeInterval ?? 300
                    let startTime = userInfo["restStartTime"] as? Date ?? Date() // 使用来自管理器的开始时间
                    updateRestTimer(rest: rest, startTime: startTime)
                } else {
                    updateWorkTimer(active: active, work: work, idle: idle)  // 传递空闲时间
                }
            }
        }
    }
    
    @objc private func onSmartReminderDisabled() {
        disableTimer()
    }
    
    /// 处理系统从休眠中唤醒
    @objc private func handleSystemWake() {
        print("🌅 StatusBarTimerView检测到系统唤醒")
        // 方案1修改：不再需要重启内部定时器
        // 显示更新完全依赖 SmartReminderManager 的通知
        print("✅ 等待接收 SmartReminderManager 的状态更新通知")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        // Timer 会在对象销毁时自动失效，无需手动停止
    }
}
