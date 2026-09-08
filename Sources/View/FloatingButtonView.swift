import Cocoa

class FloatingButtonView: NSView {
    var buttonIndex: Int = 0 {
        didSet {
            refreshConfig()
        }
    }
    private var button: NSButton!
    private var gradientLayer: CAGradientLayer!
    private var glowLayer: CAShapeLayer!
    private var rippleLayer: CAShapeLayer!
    private var lightBurstLayer: CAShapeLayer! // 光芒扩散层
    private var effectEdgeLayer: CAShapeLayer? // 特效的圆形边缘层（仅描边）
    private var isHovered = false
    private var isAnimating = false

        // 调试覆盖层，用于可视化各个元素的位置和大小
        #if DEBUG
        private var showDebugInfo = true
        #else
        private var showDebugInfo = false
        #endif
        private var debugOverlays: [CAShapeLayer] = []
        private var debugLabels: [CATextLayer] = []
        // 精确的按钮边框层（跟随按钮形状）
        private var buttonOutlineLayer: CAShapeLayer?
        // 按钮边框图层（独立于渐变层，方便控制样式）
        private var buttonBorderLayer: CAShapeLayer!
    static let floatingButtonClickedNotification = Notification.Name("floatingButtonClicked")
    static let configChangedNotification = Notification.Name("floatingButtonConfigChanged")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        setupGestures()
        setupLightBurstLayer() // 初始化光芒层
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupGestures()
    }

    deinit {
        // deinit 中无法安全地调用 MainActor 方法，跳过动画清理
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // 生产版本不显示外部容器边框
        layer?.borderColor = nil
        layer?.borderWidth = 0
        layer?.masksToBounds = false // 允许发光效果溢出

        updateSize()
        setupButton()
        setupGlowLayer()
        setupRippleLayer()
    }

    private func updateSize() {
        let configManager = FloatingButtonConfigManager.shared
        let baseSize = configManager.getButtonSize(index: buttonIndex)
        let shape = configManager.getButtonShape(index: buttonIndex)
        // 根据 shape 决定按钮的宽高：圆形使用 baseSize，胶囊使用更宽且更矮的比例
        let height: CGFloat
        let width: CGFloat
        switch shape {
        case .circle, .roundedSquare:
            height = baseSize
            width = baseSize
        case .capsule:
            height = max(18.0, baseSize * 0.6)
            // 使用较短的乘数以避免过长
            width = max(baseSize, baseSize * 1.4)
        }
        // 外层容器比按钮大，留出空间显示波纹与发光效果，随 size 变化
        let padding: CGFloat = baseSize * 0.5
        self.frame = NSRect(x: 0, y: 0, width: width + padding * 2, height: height + padding * 2)
    }

    private func setupButton() {
        let configManager = FloatingButtonConfigManager.shared
        let config = configManager.config
        let size = configManager.getButtonSize(index: buttonIndex)
        let colorScheme = configManager.getButtonColorScheme(index: buttonIndex)
        let shape = configManager.getButtonShape(index: buttonIndex)
        
        // 根据选择的形状计算按钮初始尺寸并居中放置
        let padding: CGFloat = size * 0.5
        let height: CGFloat
        let width: CGFloat
        switch shape {
        case .circle, .roundedSquare:
            height = size
            width = size
        case .capsule:
            height = max(18.0, size * 0.6)
            width = max(size, size * 1.4)
        }
        // 初始时在容器内居中放置，避免后续出现偏移
        let originX = max(padding, (self.bounds.width - width) / 2)
        let originY = max(padding, (self.bounds.height - height) / 2)
        button = NSButton(frame: NSRect(x: originX, y: originY, width: width, height: height))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.title = ""

        // 禁用按钮的鼠标事件，让窗口能够处理拖拽
        button.isEnabled = false

        // 设置渐变背景
        gradientLayer = CAGradientLayer()
        gradientLayer.frame = button.bounds
        
        // 使用配置中的形状绘制（支持圆形、胶囊等）
        let buttonRect = button.bounds
        let shapePath = shape.path(in: buttonRect)

        // 创建形状层并作为渐变的 mask
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = shapePath
        shapeLayer.frame = CGRect(origin: .zero, size: buttonRect.size)

        // 设置渐变
        gradientLayer.colors = [
            colorScheme.startColor,
            colorScheme.endColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.mask = shapeLayer

        // 为按钮添加边框/圆角的可视化（仍以 mask 为主以支持任意形状）
        gradientLayer.borderWidth = 0
        gradientLayer.masksToBounds = true

        button.layer = gradientLayer

        // 调试边框已移除（生产中不再显示按钮外边框）
        // 如果需要在调试时再次显示，可以设置 showDebugInfo = true 并在此处恢复边框创建逻辑。

        // 设置图标或文字
        if let action = config.buttonActions[buttonIndex] {
            if config.displayMode == .textOnly {
                // 显示文字
                let title = action.localizedName
                let fontSize = size * 0.3
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: NSColor(cgColor: colorScheme.contentTintColor) ?? .white
                ]
                let attributedTitle = NSAttributedString(string: title, attributes: attributes)
                button.attributedTitle = attributedTitle
                button.image = nil
            } else {
                // 显示图标
                let iconName = config.customIcons[buttonIndex] ?? action.iconName
                if let iconName = iconName {
                    let iconConfig = NSImage.SymbolConfiguration(pointSize: size * 0.4, weight: .medium)
                    if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(iconConfig) {
                        button.image = icon
                        button.imagePosition = .imageOnly
                        button.contentTintColor = NSColor(cgColor: colorScheme.contentTintColor)
                    }
                }
            }
        }

        // 悬停效果
        button.wantsLayer = true

        addSubview(button)
    }

    private func setupGlowLayer() {
        let configManager = FloatingButtonConfigManager.shared
        let size = configManager.getButtonSize(index: buttonIndex)
        let colorScheme = configManager.getButtonColorScheme(index: buttonIndex)
        
        glowLayer = CAShapeLayer()
        let padding: CGFloat = size * 0.5
        // 使用与按钮一致的大小，确保发光紧贴按钮边缘
        let glowRect = bounds.insetBy(dx: padding, dy: padding)
        glowLayer.frame = glowRect
        
        let glowShape = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex)
        glowLayer.path = glowShape.path(in: glowLayer.bounds)
        glowLayer.fillColor = NSColor.clear.cgColor
        
        // 配置外发光特效，半径随 size 变化
        let glowColor = colorScheme.endColor
        glowLayer.shadowColor = glowColor
        glowLayer.shadowRadius = size * 0.1     // 进一步缩小动态发光半径
        glowLayer.shadowOpacity = 1.0   // 增加不透明度让发光更明显
        glowLayer.shadowOffset = .zero  // 居中发光
        
        // 描边作为发光源
        glowLayer.strokeColor = glowColor
        glowLayer.lineWidth = 2.0 // 稍微加粗描边以增强阴影源
        
        glowLayer.opacity = 0
        
        // 将发光层放在最底层，使其作为背景发光
        layer?.insertSublayer(glowLayer, at: 0)
        
        // 确保父视图不裁剪内容，否则发光会被切掉
        layer?.masksToBounds = false
    }

    private func setupRippleLayer() {
        let configManager = FloatingButtonConfigManager.shared
        let colorScheme = configManager.getButtonColorScheme(index: buttonIndex)
        
        rippleLayer = CAShapeLayer()
        // rippleLayer 充满整个容器
        rippleLayer.frame = bounds
        let shape = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex)
        rippleLayer.path = shape.path(in: bounds)
        
        // 使用更柔和的波纹效果，完全去除阴影
        let rippleColor = colorScheme.startColor
        rippleLayer.fillColor = NSColor(cgColor: rippleColor)?.withAlphaComponent(0.2).cgColor ?? rippleColor
        rippleLayer.opacity = 0
        rippleLayer.shadowColor = nil   // 完全去除波纹阴影
        rippleLayer.shadowRadius = 0
        rippleLayer.shadowOpacity = 0
        rippleLayer.shadowOffset = .zero
        rippleLayer.shouldRasterize = true // 提高性能
        rippleLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.addSublayer(rippleLayer)
    }
    
    private func setupLightBurstLayer() {
        let colorScheme = FloatingButtonConfigManager.shared.getButtonColorScheme(index: buttonIndex)

        lightBurstLayer = CAShapeLayer()
        // 光芒层充满整个容器
        lightBurstLayer.frame = bounds
        let shape = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex)
        lightBurstLayer.path = shape.path(in: bounds)

        // 设置光芒初始状态
        lightBurstLayer.fillColor = NSColor.clear.cgColor
        lightBurstLayer.strokeColor = NSColor.clear.cgColor // 保持初始不可见
        lightBurstLayer.lineWidth = 3
        lightBurstLayer.opacity = 0
        lightBurstLayer.shouldRasterize = true
        lightBurstLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // 添加光芒层，然后调整层级关系
        layer?.addSublayer(lightBurstLayer)
        layer?.insertSublayer(lightBurstLayer, below: rippleLayer) // 放在波纹层下面

        // 创建一个专门的边缘描边层（仅描边、无填充），用于显示与按钮形状一致的边缘特效
        effectEdgeLayer = CAShapeLayer()
        let shapeForEdge = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex)
        if let btn = button {
            effectEdgeLayer?.frame = btn.frame
            effectEdgeLayer?.path = shapeForEdge.path(in: CGRect(origin: .zero, size: btn.bounds.size))
        } else {
            effectEdgeLayer?.frame = bounds
            effectEdgeLayer?.path = shapeForEdge.path(in: bounds)
        }
        effectEdgeLayer?.fillColor = NSColor.clear.cgColor
        let edgeColor = NSColor(cgColor: colorScheme.endColor) ?? NSColor.white
        effectEdgeLayer?.strokeColor = edgeColor.withAlphaComponent(0.6).cgColor
        effectEdgeLayer?.lineWidth = 2
        effectEdgeLayer?.opacity = 0 // 默认隐藏
        effectEdgeLayer?.shouldRasterize = true
        effectEdgeLayer?.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if let edge = effectEdgeLayer {
            layer?.addSublayer(edge)
            layer?.insertSublayer(edge, above: lightBurstLayer)
        }
    }

    // MARK: - Debug overlay for frames/sizes
    private func setupDebugOverlay() {
        guard showDebugInfo else { return }
        // 移除已有调试层
        debugOverlays.forEach { $0.removeFromSuperlayer() }
        debugLabels.forEach { $0.removeFromSuperlayer() }
        debugOverlays.removeAll()
        debugLabels.removeAll()

        func addOutline(rect: CGRect, color: NSColor, name: String) {
            let outline = CAShapeLayer()
            outline.frame = rect
            outline.path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
            outline.strokeColor = color.withAlphaComponent(0.9).cgColor
            outline.fillColor = NSColor.clear.cgColor
            outline.lineWidth = 1
            outline.lineDashPattern = [4, 2]
            outline.name = name
            layer?.addSublayer(outline)
            debugOverlays.append(outline)

            let label = CATextLayer()
            label.string = "\(name): \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))"
            label.fontSize = 10
            label.foregroundColor = NSColor.white.cgColor
            label.backgroundColor = color.withAlphaComponent(0.6).cgColor
            label.alignmentMode = .left
            label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            label.frame = CGRect(x: rect.origin.x, y: min(rect.origin.y + rect.size.height + 4, bounds.height - 16), width: 220, height: 14)
            layer?.addSublayer(label)
            debugLabels.append(label)
        }

        addOutline(rect: bounds, color: .red, name: "container")
        addOutline(rect: button.frame, color: .orange, name: "button")
        addOutline(rect: button.frame, color: .yellow, name: "gradient")
        if let glow = glowLayer { addOutline(rect: glow.frame, color: .purple, name: "glow") }
        if let ripple = rippleLayer { addOutline(rect: ripple.frame, color: .blue, name: "ripple") }
        if let light = lightBurstLayer { addOutline(rect: light.frame, color: .green, name: "light") }
        if let edge = effectEdgeLayer { addOutline(rect: edge.frame, color: .magenta, name: "edge") }

        updateDebugOverlay()
    }

    private func updateDebugOverlay() {
        guard showDebugInfo else { return }
        for (index, outline) in debugOverlays.enumerated() {
            guard let name = outline.name else { continue }
            switch name {
            case "container":
                outline.frame = bounds
                outline.path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
                debugLabels[index].string = "container: \(Int(bounds.origin.x)),\(Int(bounds.origin.y)) \(Int(bounds.width))x\(Int(bounds.height))"
                debugLabels[index].frame.origin = CGPoint(x: 2, y: bounds.height - 18)
            case "button", "gradient":
                let rect = button.frame
                outline.frame = rect
                outline.path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
                debugLabels[index].string = "\(name): \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))"
                debugLabels[index].frame.origin = CGPoint(x: rect.origin.x, y: rect.origin.y + rect.size.height + 4)
            case "glow":
                if let glow = glowLayer {
                    let rect = glow.frame
                    outline.frame = rect
                    outline.path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
                    debugLabels[index].string = "glow: \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))"
                    debugLabels[index].frame.origin = CGPoint(x: rect.origin.x, y: rect.origin.y + rect.size.height + 4)
                }
            case "ripple":
                if let ripple = rippleLayer {
                    let rect = ripple.frame
                    outline.frame = rect
                    outline.path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
                    debugLabels[index].string = "ripple: \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))"
                    debugLabels[index].frame.origin = CGPoint(x: rect.origin.x, y: rect.origin.y + rect.size.height + 4)
                }
            case "light":
                if let light = lightBurstLayer {
                    let rect = light.frame
                    outline.frame = rect
                    outline.path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
                    debugLabels[index].string = "light: \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))"
                    debugLabels[index].frame.origin = CGPoint(x: rect.origin.x, y: rect.origin.y + rect.size.height + 4)
                }
            case "edge":
                if let edge = effectEdgeLayer {
                    let rect = edge.frame
                    outline.frame = rect
                    outline.path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
                    debugLabels[index].string = "edge: \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))"
                    debugLabels[index].frame.origin = CGPoint(x: rect.origin.x, y: rect.origin.y + rect.size.height + 4)
                }
            default: break
            }
        }
    }

    // layout 已在文件末尾统一处理，避免重复定义。

    private func setupGestures() {
        // 添加鼠标进入事件
        _ = NSEvent.addGlobalMonitorForEvents(matching: .mouseEntered) { [weak self] event in
            guard let self = self else { return }
            if let window = self.window, let contentView = window.contentView, contentView == self {
                self.handleMouseEntered()
            }
        }

        // 添加鼠标离开事件
        _ = NSEvent.addGlobalMonitorForEvents(matching: .mouseExited) { [weak self] event in
            guard let self = self else { return }
            if let window = self.window, let contentView = window.contentView, contentView == self {
                self.handleMouseExited()
            }
        }

        // 添加点击手势识别器
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(clickGesture)
    }

    private func handleMouseEntered() {
        guard !isHovered else { return }
        isHovered = true

        // 稍稍放大动画
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 1.1
        scaleAnimation.duration = 0.2
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scaleAnimation.fillMode = .forwards
        scaleAnimation.isRemovedOnCompletion = false

        button.layer?.add(scaleAnimation, forKey: "hoverScale")

        // 更柔和的发光层淡入
        let glowFadeIn = CABasicAnimation(keyPath: "opacity")
        glowFadeIn.fromValue = 0
        glowFadeIn.toValue = 1.0
        glowFadeIn.duration = 0.3
        glowFadeIn.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        glowFadeIn.fillMode = .forwards
        glowFadeIn.isRemovedOnCompletion = false
        glowLayer?.add(glowFadeIn, forKey: "glowFadeIn")

        // 特效边缘淡入
        if let edge = effectEdgeLayer {
            let edgeFade = CABasicAnimation(keyPath: "opacity")
            edgeFade.fromValue = 0
            edgeFade.toValue = 1
            edgeFade.duration = 0.25
            edgeFade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            edgeFade.fillMode = .forwards
            edgeFade.isRemovedOnCompletion = false
            edge.add(edgeFade, forKey: "edgeFadeIn")
        }
        
        // 去除阴影动画，只保留纯发光效果
        // glowLayer?.add(shadowFadeIn, forKey: "shadowFadeIn")
    }

    private func handleMouseExited() {
        guard isHovered else { return }
        isHovered = false

        // 恢复大小动画
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.1
        scaleAnimation.toValue = 1.0
        scaleAnimation.duration = 0.2
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scaleAnimation.fillMode = .forwards
        scaleAnimation.isRemovedOnCompletion = false

        button.layer?.add(scaleAnimation, forKey: "hoverScaleExit")

        // 更柔和的发光层淡出
        let glowFadeOut = CABasicAnimation(keyPath: "opacity")
        glowFadeOut.fromValue = 1.0
        glowFadeOut.toValue = 0
        glowFadeOut.duration = 0.3
        glowFadeOut.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        glowFadeOut.fillMode = .forwards
        glowFadeOut.isRemovedOnCompletion = false
        glowLayer?.add(glowFadeOut, forKey: "glowFadeOut")

        // 特效边缘淡出
        if let edge = effectEdgeLayer {
            let edgeFade = CABasicAnimation(keyPath: "opacity")
            edgeFade.fromValue = 1
            edgeFade.toValue = 0
            edgeFade.duration = 0.2
            edgeFade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            edgeFade.fillMode = .forwards
            edgeFade.isRemovedOnCompletion = false
            edge.add(edgeFade, forKey: "edgeFadeOut")
        }
        
        // 去除阴影动画，只保留纯发光效果
        // glowLayer?.add(shadowFadeOut, forKey: "shadowFadeOut")
    }

    @objc private func handleClick() {
        Logger.shared.log("🖱️ FloatingButtonView.handleClick: buttonIndex=\(buttonIndex)")
        // 发送点击通知
        NotificationCenter.default.post(name: Self.floatingButtonClickedNotification, object: self)
        Logger.shared.log("📤 已发送点击通知")

        // 点击弹性动画
        performClickAnimation()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        for action in FloatingButtonConfig.ButtonAction.allCases where action != .plugin && action != .showReminder {
            let item = NSMenuItem(title: action.localizedName, action: #selector(selectAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action

            // 检查当前是否选中
            let currentAction = FloatingButtonConfigManager.shared.config.buttonActions[buttonIndex] ?? .none
            if action == currentAction {
                item.state = .on
            }

            menu.addItem(item)
        }

        // 如果当前是控制窗口模式，添加绑定窗口选项
        let currentAction = FloatingButtonConfigManager.shared.config.buttonActions[buttonIndex] ?? .none
        if currentAction == .toggleWindow {
            menu.addItem(NSMenuItem.separator())
            let config = FloatingButtonConfigManager.shared.config
            if config.boundWindows[buttonIndex] != nil {
                let clearItem = NSMenuItem(title: L10n.tr("button.rebindWindow"), action: #selector(rebindWindow), keyEquivalent: "")
                clearItem.target = self
                menu.addItem(clearItem)
            } else {
                let bindItem = NSMenuItem(title: L10n.tr("button.bindWindow"), action: #selector(bindWindow), keyEquivalent: "")
                bindItem.target = self
                menu.addItem(bindItem)
            }
        }

        if let group = FloatingButtonConfigManager.shared.getGroup(for: buttonIndex), group.memberIndices.count > 1 {
            menu.addItem(NSMenuItem.separator())
            let arrangeGroupItem = NSMenuItem(title: L10n.tr("button.arrangeGroup"), action: #selector(arrangeGroupFromMenu(_:)), keyEquivalent: "")
            arrangeGroupItem.target = self
            menu.addItem(arrangeGroupItem)
        }

        if currentAction == .executeHotkey {
            menu.addItem(NSMenuItem.separator())
            let currentHotkey = FloatingButtonConfigManager.shared.config.buttonHotkeys[buttonIndex] ?? ""
            let bindTitle = currentHotkey.isEmpty ? "绑定快捷键" : "修改快捷键"
            let bindItem = NSMenuItem(title: bindTitle, action: #selector(editHotkeyBindingFromMenu(_:)), keyEquivalent: "")
            bindItem.target = self
            menu.addItem(bindItem)

            if !currentHotkey.isEmpty {
                let clearItem = NSMenuItem(title: L10n.tr("button.clearHotkey"), action: #selector(clearHotkeyBindingFromMenu(_:)), keyEquivalent: "")
                clearItem.target = self
                menu.addItem(clearItem)
            }
        }

        // 添加个性化设置选项
        menu.addItem(NSMenuItem.separator())
        let customizeItem = NSMenuItem(title: L10n.tr("button.customize"), action: #selector(openCustomizationPanel), keyEquivalent: "")
        customizeItem.target = self
        menu.addItem(customizeItem)

        // 添加隐藏和删除选项
        menu.addItem(NSMenuItem.separator())
        let hideItem = NSMenuItem(title: L10n.tr("button.hideButton"), action: #selector(hideFloatingButton), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        // 如果只剩一个按钮，不显示删除选项
        if FloatingButtonConfigManager.shared.config.buttonCount > 1 {
            let deleteItem = NSMenuItem(title: L10n.tr("button.deleteButton"), action: #selector(deleteFloatingButton), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
        }

        // 添加测试新方案入口
        menu.addItem(NSMenuItem.separator())
        let testItem = NSMenuItem(title: L10n.tr("button.createGlow"), action: #selector(spawnGlowFloatingButton), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func spawnGlowFloatingButton() {
        Logger.shared.log("🧪 Spawning Glow Floating Button")
        
        let buttonSize: CGFloat = 50
        let padding: CGFloat = 60 // 给予足够的空间显示发光，防止边缘裁剪
        let windowSize = buttonSize + padding * 2
        
        // 创建一个新的无边框窗口
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: windowSize, height: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true // 允许拖动背景移动窗口
        
        let glowView = GlowFloatingButtonView(frame: NSRect(x: 0, y: 0, width: windowSize, height: windowSize))
        window.contentView = glowView
        
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        // 保持窗口引用，防止被释放（简单演示用，实际应由管理器管理）
        // 这里利用 window 自身的生命周期，如果不被引用可能会立即释放，但在 macOS App 中 window 显示后通常会被 window server 持有，或者我们可以暂时挂在 NSApp.windows 中
        // 为了保险，我们可以将其添加到一个简单的静态数组中保持引用
        GlowWindowManager.shared.addWindow(window)
    }


    @objc private func bindWindow() {
        Logger.shared.log("🔗 bindWindow: buttonIndex=\(buttonIndex)")
        WindowManager.shared.startWindowSelection(for: buttonIndex)
    }
    
    @objc private func rebindWindow() {
        Logger.shared.log("🔄 rebindWindow: buttonIndex=\(buttonIndex)")
        WindowManager.shared.startWindowSelection(for: buttonIndex)
    }

    @objc private func arrangeGroupFromMenu(_ sender: NSMenuItem) {
        NotificationCenter.default.post(name: Notification.Name("arrangeGroupMembers"), object: buttonIndex)
    }

    @objc private func editHotkeyBindingFromMenu(_ sender: NSMenuItem) {
        let configManager = FloatingButtonConfigManager.shared
        let currentHotkey = configManager.config.buttonHotkeys[buttonIndex] ?? ""

        let alert = NSAlert()
        alert.messageText = L10n.tr("button.bindHotkey")
        alert.informativeText = L10n.tr("button.hotkeyFormat")

        let inputField = NSTextField(string: currentHotkey)
        inputField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        inputField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        alert.accessoryView = inputField

        alert.addButton(withTitle: L10n.tr("common.save"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            let hotkey = inputField.stringValue
            configManager.updateButtonHotkey(index: buttonIndex, hotkey: hotkey)
        }
    }

    @objc private func clearHotkeyBindingFromMenu(_ sender: NSMenuItem) {
        FloatingButtonConfigManager.shared.updateButtonHotkey(index: buttonIndex, hotkey: "")
    }

    @objc private func selectAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? FloatingButtonConfig.ButtonAction else {
            Logger.shared.log("❌ selectAction: 无法获取操作类型")
            return
        }
        Logger.shared.log("🎯 selectAction: buttonIndex=\(buttonIndex), action=\(action.rawValue)")
        FloatingButtonConfigManager.shared.updateButtonAction(index: buttonIndex, action: action)
        Logger.shared.log("💾 配置已更新")
    }

    @objc private func hideFloatingButton() {
        Logger.shared.log("👁️ hideFloatingButton: buttonIndex=\(buttonIndex)")
        // 隐藏悬浮球窗口
        if let window = self.window {
            window.orderOut(nil)
        }
    }

    @objc private func deleteFloatingButton() {
        Logger.shared.log("🗑️ deleteFloatingButton: buttonIndex=\(buttonIndex)")
        // 通过通知 AppDelegate 来删除指定索引的悬浮球
        NotificationCenter.default.post(name: Notification.Name("deleteFloatingButton"), object: nil, userInfo: ["buttonIndex": buttonIndex])
    }

    @objc private func openCustomizationPanel() {
        Logger.shared.log("🎨 openCustomizationPanel: buttonIndex=\(buttonIndex)")

        let windowRect = NSRect(x: 0, y: 0, width: 350, height: 400)
        let customizationWindow = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        customizationWindow.title = "悬浮球 \(buttonIndex + 1) 个性化设置"
        customizationWindow.level = .floating
        customizationWindow.isReleasedWhenClosed = false

        let contentView = NSView(frame: windowRect)
        customizationWindow.contentView = contentView

        let configManager = FloatingButtonConfigManager.shared
        let currentCustomization = configManager.config.buttonCustomizations[buttonIndex] ?? FloatingButtonConfig.ButtonCustomization()

        // 大小设置
        let sizeLabel = NSTextField(labelWithString: "大小:")
        sizeLabel.frame = NSRect(x: 20, y: 340, width: 60, height: 24)
        contentView.addSubview(sizeLabel)

        let sizeSlider = NSSlider(
            value: Double(currentCustomization.size ?? configManager.config.size),
            minValue: Double(FloatingButtonConfig.minSize),
            maxValue: Double(FloatingButtonConfig.maxSize),
            target: self,
            action: #selector(customSizeChanged(_:))
        )
        sizeSlider.frame = NSRect(x: 90, y: 340, width: 180, height: 24)
        sizeSlider.tag = 1000 + buttonIndex // 专属 Tag
        contentView.addSubview(sizeSlider)

        let sizeValueLabel = NSTextField(labelWithString: "\(Int(currentCustomization.size ?? configManager.config.size))px")
        sizeValueLabel.frame = NSRect(x: 280, y: 340, width: 60, height: 24)
        sizeValueLabel.tag = 4000 + buttonIndex
        contentView.addSubview(sizeValueLabel)

        // 颜色主题设置
        let colorLabel = NSTextField(labelWithString: "颜色主题:")
        colorLabel.frame = NSRect(x: 20, y: 290, width: 80, height: 24)
        contentView.addSubview(colorLabel)

        let colorPopup = NSPopUpButton(frame: NSRect(x: 110, y: 290, width: 200, height: 24))
        colorPopup.tag = 2000 + buttonIndex
        colorPopup.addItem(withTitle: L10n.tr("button.useGlobalSettings"))
        for scheme in FloatingButtonConfig.ColorScheme.allCases {
            colorPopup.addItem(withTitle: scheme.localizedName)
        }
        
        if let customScheme = currentCustomization.colorScheme {
            if let index = FloatingButtonConfig.ColorScheme.allCases.firstIndex(of: customScheme) {
                colorPopup.selectItem(at: index + 1)
            }
        } else {
            colorPopup.selectItem(at: 0)
        }
        
        colorPopup.target = self
        colorPopup.action = #selector(customColorChanged(_:))
        contentView.addSubview(colorPopup)

        // 形状设置
        let shapeLabel = NSTextField(labelWithString: "形状:")
        shapeLabel.frame = NSRect(x: 20, y: 240, width: 60, height: 24)
        contentView.addSubview(shapeLabel)

        let shapePopup = NSPopUpButton(frame: NSRect(x: 90, y: 240, width: 200, height: 24))
        shapePopup.tag = 3000 + buttonIndex
        for shape in FloatingButtonConfig.ButtonShape.allCases {
            shapePopup.addItem(withTitle: shape.localizedName)
        }
        
        if let customShape = currentCustomization.shape {
            if let index = FloatingButtonConfig.ButtonShape.allCases.firstIndex(of: customShape) {
                shapePopup.selectItem(at: index)
            }
        } else {
            // 默认选中圆形
            let defaultShape = FloatingButtonConfig.ButtonShape.circle
            if let index = FloatingButtonConfig.ButtonShape.allCases.firstIndex(of: defaultShape) {
                shapePopup.selectItem(at: index)
            }
        }
        
        shapePopup.target = self
        shapePopup.action = #selector(customShapeChanged(_:))
        contentView.addSubview(shapePopup)

        // 重置按钮
        let resetButton = NSButton(title: L10n.tr("button.resetToDefault"), target: self, action: #selector(resetCustomization(_:)))
        resetButton.frame = NSRect(x: 20, y: 20, width: 100, height: 32)
        resetButton.tag = buttonIndex
        contentView.addSubview(resetButton)

        // 应用按钮
        let applyButton = NSButton(title: L10n.tr("common.apply"), target: self, action: #selector(applyCustomization(_:)))
        applyButton.frame = NSRect(x: 230, y: 20, width: 100, height: 32)
        applyButton.tag = buttonIndex
        applyButton.keyEquivalent = "\r"
        contentView.addSubview(applyButton)

        customizationWindow.center()
        customizationWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func customSizeChanged(_ sender: NSSlider) {
        let newSize = CGFloat(sender.doubleValue)
        let index = sender.tag - 1000
        if let window = sender.window, let valueLabel = window.contentView?.viewWithTag(4000 + index) as? NSTextField {
            valueLabel.stringValue = "\(Int(newSize))px"
        }
    }

    @objc private func customColorChanged(_ sender: NSPopUpButton) {
        // 颜色变化处理在应用时进行
    }

    @objc private func customShapeChanged(_ sender: NSPopUpButton) {
        // 形状变化处理在应用时进行
    }

    @objc private func resetCustomization(_ sender: NSButton) {
        let index = sender.tag
        FloatingButtonConfigManager.shared.updateButtonCustomization(index: index, customization: FloatingButtonConfig.ButtonCustomization())
        sender.window?.close()
    }

    @objc private func applyCustomization(_ sender: NSButton) {
        let index = sender.tag
        guard let window = sender.window, let contentView = window.contentView else { return }
        
        let configManager = FloatingButtonConfigManager.shared
        // 重要：先获取现有的定制化设置
        var customization = configManager.config.buttonCustomizations[index] ?? FloatingButtonConfig.ButtonCustomization()
        
        // 获取大小设置 (Tag 1000 偏移)
        if let sizeSlider = contentView.viewWithTag(1000 + index) as? NSSlider {
            let newSize = CGFloat(sizeSlider.doubleValue)
            customization.size = newSize
        }
        
        // 获取颜色设置 (Tag 2000 偏移)
        if let colorPopup = contentView.viewWithTag(2000 + index) as? NSPopUpButton {
            if colorPopup.indexOfSelectedItem > 0 {
                let schemeIndex = colorPopup.indexOfSelectedItem - 1
                let allSchemes = FloatingButtonConfig.ColorScheme.allCases
                if schemeIndex >= 0 && schemeIndex < allSchemes.count {
                    customization.colorScheme = allSchemes[schemeIndex]
                }
            } else {
                customization.colorScheme = nil
            }
        }
        
        // 获取形状设置 (Tag 3000 偏移)
        if let shapePopup = contentView.viewWithTag(3000 + index) as? NSPopUpButton {
            let shapeIndex = shapePopup.indexOfSelectedItem
            let allShapes = FloatingButtonConfig.ButtonShape.allCases
            if shapeIndex >= 0 && shapeIndex < allShapes.count {
                customization.shape = allShapes[shapeIndex]
            }
        }
        
        configManager.updateButtonCustomization(index: index, customization: customization)
        window.close()
    }

    private func performClickAnimation() {
        // 只保留温润的缩放动画
        performClickScale()
    }
    
    private func performClickScale() {
        // 更自然的缩放：先轻微缩小，然后弹性恢复
        let scaleDown = CABasicAnimation(keyPath: "transform.scale")
        scaleDown.fromValue = 1.0
        scaleDown.toValue = 0.95  // 缩小幅度减小，更自然
        scaleDown.duration = 0.1   // 稍微延长一点
        scaleDown.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1) // 更柔和的缓动
        scaleDown.fillMode = .forwards
        scaleDown.isRemovedOnCompletion = false

        let scaleUp = CASpringAnimation(keyPath: "transform.scale")
        scaleUp.fromValue = 0.95
        scaleUp.toValue = 1.0
        scaleUp.duration = 0.6     // 延长弹性时间
        scaleUp.mass = 0.8         // 减小质量，更轻盈
        scaleUp.stiffness = 150     // 降低刚度，更柔软
        scaleUp.damping = 8         // 减小阻尼，更有弹性
        scaleUp.initialVelocity = 0.3 // 添加初始速度
        
        let scaleGroup = CAAnimationGroup()
        scaleGroup.animations = [scaleDown, scaleUp]
        scaleGroup.duration = 0.6
        scaleGroup.fillMode = .forwards
        scaleGroup.isRemovedOnCompletion = false
        
        button.layer?.add(scaleGroup, forKey: "clickScale")
    }

    private func performRippleAnimation() {
        let config = FloatingButtonConfigManager.shared.config
        let colorScheme = config.colorScheme
        let rippleColor = colorScheme.startColor

        // 波纹从按钮中心开始
        let centerX = bounds.midX
        let centerY = bounds.midY
        let btnFrame = button.frame
        let initialRadius = btnFrame.width / 2

        // 创建从按钮当前形状和大小开始的路径
        let shape = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex)
        let initialPath = shape.path(in: CGRect(
            x: centerX - btnFrame.width / 2,
            y: centerY - btnFrame.height / 2,
            width: btnFrame.width,
            height: btnFrame.height
        ))

        rippleLayer?.path = initialPath
        
        // 更水滴感的初始颜色和透明度
        rippleLayer?.fillColor = NSColor(cgColor: rippleColor)?.withAlphaComponent(0.25).cgColor ?? rippleColor
        rippleLayer?.opacity = 0

        // 水滴涟漪的扩散范围 - 更自然的大小
        let padding: CGFloat = 40
        let maxExpansion = btnFrame.width + padding * 2.2 // 扩散到更自然的范围
        let maxRadius = maxExpansion / 2

        // 水滴扩散动画 - 更自然的缓动
        let rippleScale = CASpringAnimation(keyPath: "transform.scale")
        rippleScale.fromValue = 1.0
        rippleScale.toValue = maxRadius / initialRadius
        rippleScale.duration = 0.8
        rippleScale.mass = 1.2
        rippleScale.stiffness = 80   // 更柔软，像水
        rippleScale.damping = 6       // 更多涟漪感
        rippleScale.initialVelocity = 0.5
        
        // 统一设置 AnchorPoint 以中心扩散
        rippleLayer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // 水滴淡出动画 - 模拟水波消失
        let rippleFade = CAKeyframeAnimation(keyPath: "opacity")
        rippleFade.values = [0, 0.25, 0.15, 0.08, 0] // 水波般的透明度变化
        rippleFade.keyTimes = [0, 0.1, 0.4, 0.7, 1.0]   // 对应的时间点
        rippleFade.duration = 0.8

        let rippleGroup = CAAnimationGroup()
        rippleGroup.animations = [rippleScale, rippleFade]
        rippleGroup.duration = 0.8
        rippleGroup.fillMode = .forwards
        rippleGroup.isRemovedOnCompletion = false
        
        // 更自然的延迟启动，模拟水滴落下后的涟漪
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.rippleLayer?.add(rippleGroup, forKey: "ripple")
        }
    }
    
    private func performLightBurstAnimation() {
        let colorScheme = FloatingButtonConfigManager.shared.getButtonColorScheme(index: buttonIndex)
        let burstColor = colorScheme.endColor // 使用主题结束色作为光芒色
        
        // 设置光芒颜色 - 更亮的版本
        lightBurstLayer?.strokeColor = NSColor(cgColor: burstColor)?.withAlphaComponent(0.8).cgColor ?? burstColor
        lightBurstLayer?.fillColor = NSColor(cgColor: burstColor)?.withAlphaComponent(0.3).cgColor ?? burstColor
        
        // 光芒从按钮大小开始
        let centerX = bounds.midX
        let centerY = bounds.midY
        let btnFrame = button.frame
        let initialRadius = btnFrame.width / 2
        
        // 创建初始路径（按钮实际大小且跟随形状）
        let shape = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex)
        let initialBurstPath = shape.path(in: CGRect(
            x: centerX - btnFrame.width / 2,
            y: centerY - btnFrame.height / 2,
            width: btnFrame.width,
            height: btnFrame.height
        ))
        
        lightBurstLayer?.path = initialBurstPath
        lightBurstLayer?.opacity = 0
        lightBurstLayer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        // 光芒扩散到更大的范围
        let padding: CGFloat = 25
        let maxBurstExpansion = btnFrame.width + padding * 2.8 // 光芒扩散得更远
        let maxBurstRadius = maxBurstExpansion / 2
        
        // 光芒缩放动画 - 更快更锐利的扩散
        let burstScale = CABasicAnimation(keyPath: "transform.scale")
        burstScale.fromValue = 1.0
        burstScale.toValue = maxBurstRadius / initialRadius
        burstScale.duration = 0.4 // 快速扩散
        burstScale.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
        
        // 光芒透明度动画 - 先亮后灭
        let burstOpacity = CAKeyframeAnimation(keyPath: "opacity")
        burstOpacity.values = [0, 0.9, 0.6, 0.2, 0] // 快速变亮然后熄灭
        burstOpacity.keyTimes = [0, 0.1, 0.3, 0.6, 1.0] // 时间分布
        burstOpacity.duration = 0.4
        
        // 光芒颜色变化动画 - 从亮到暗
        let colorAnimation = CAKeyframeAnimation(keyPath: "strokeColor")
        let startColor = NSColor(cgColor: burstColor)?.withAlphaComponent(0.8).cgColor ?? burstColor
        let midColor = NSColor(cgColor: burstColor)?.withAlphaComponent(0.5).cgColor ?? burstColor
        let endColor = NSColor(cgColor: burstColor)?.withAlphaComponent(0.1).cgColor ?? burstColor
        colorAnimation.values = [startColor, midColor, endColor]
        colorAnimation.keyTimes = [0, 0.5, 1.0]
        colorAnimation.duration = 0.4
        
        // 组合动画
        let burstGroup = CAAnimationGroup()
        burstGroup.animations = [burstScale, burstOpacity, colorAnimation]
        burstGroup.duration = 0.4
        burstGroup.fillMode = .forwards
        burstGroup.isRemovedOnCompletion = false
        
        // 稍微延迟启动，与按钮动画配合
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.lightBurstLayer?.add(burstGroup, forKey: "lightBurst")
        }
    }

    private func performPulseAnimation() {
        // 脉冲发光
        let pulseFadeIn = CABasicAnimation(keyPath: "opacity")
        pulseFadeIn.fromValue = 0
        pulseFadeIn.toValue = 0.8
        pulseFadeIn.duration = 0.15
        pulseFadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let pulseFadeOut = CABasicAnimation(keyPath: "opacity")
        pulseFadeOut.fromValue = 0.8
        pulseFadeOut.toValue = 0
        pulseFadeOut.duration = 0.3
        pulseFadeOut.beginTime = CACurrentMediaTime() + 0.15
        pulseFadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let pulseGroup = CAAnimationGroup()
        pulseGroup.animations = [pulseFadeIn, pulseFadeOut]
        pulseGroup.duration = 0.45
        pulseGroup.fillMode = .forwards
        pulseGroup.isRemovedOnCompletion = false

        glowLayer?.add(pulseGroup, forKey: "pulse")
    }

    // MARK: - 灵动动画

    private var displayLink: CADisplayLink?

    func refreshConfig() {
        // 先移除旧的 layer
        glowLayer?.removeFromSuperlayer()
        rippleLayer?.removeFromSuperlayer()
        lightBurstLayer?.removeFromSuperlayer()
        effectEdgeLayer?.removeFromSuperlayer()
        effectEdgeLayer = nil
        // 移除按钮外边框（同时移除可能存在的按钮内部边框）
        buttonOutlineLayer?.removeFromSuperlayer()
        buttonOutlineLayer = nil
        buttonBorderLayer?.removeFromSuperlayer()
        buttonBorderLayer = nil

        // 更新大小
        updateSize()

        // 移除旧按钮
        button?.removeFromSuperview()

        // 重新创建按钮
        setupButton()

        // 重新创建 glowLayer、rippleLayer 和 lightBurstLayer（使用新主题色）
        setupGlowLayer()
        setupRippleLayer()
        setupLightBurstLayer()

        // 更新圆角遮罩
        updateMaskLayer()
    }

    private func updateMaskLayer() {
        if let window = window as? FloatingWindow {
            window.updateMask(for: bounds.size)
        }
    }

    override func layout() {
        super.layout()

        let configManager = FloatingButtonConfigManager.shared
        let baseSize = configManager.getButtonSize(index: buttonIndex)
        let padding: CGFloat = 25
        let shape = configManager.getButtonShape(index: buttonIndex)

        // 根据 shape 决定按钮的宽高
        let height: CGFloat
        let width: CGFloat
        switch shape {
        case .circle, .roundedSquare:
            height = baseSize
            width = baseSize
        case .capsule:
            height = max(18.0, baseSize * 0.6)
            width = max(baseSize, baseSize * 1.4)
        }

        // 按钮居中显示于容器中
        let originX = (bounds.width - width) / 2
        let originY = (bounds.height - height) / 2
        button?.frame = NSRect(x: originX, y: originY, width: width, height: height)
        button?.layer?.frame = button?.bounds ?? .zero

        gradientLayer?.frame = button?.bounds ?? .zero
        // 更新 gradient 的 mask 路径以匹配当前形状
        if let mask = gradientLayer?.mask as? CAShapeLayer, let btn = button {
            mask.frame = CGRect(origin: .zero, size: btn.bounds.size)
            mask.path = shape.path(in: CGRect(origin: .zero, size: btn.bounds.size))
        }
        // glowLayer 围绕按钮，使用与按钮一致的大小以产生外发光效果
        let glowInset: CGFloat = padding
        let glowRect = bounds.insetBy(dx: glowInset, dy: glowInset)
        glowLayer?.frame = glowRect
        let shapeForGlow = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex)
        glowLayer?.path = shapeForGlow.path(in: glowLayer?.bounds ?? .zero)
        if shapeForGlow == .circle {
            glowLayer?.cornerRadius = glowRect.height / 2
        } else {
            glowLayer?.cornerRadius = 0
        }

        // 更新按钮边框图层（使用配置的形状）
        if let _ = buttonBorderLayer, let btn = button {
            let buttonRect = btn.bounds
            buttonBorderLayer?.frame = buttonRect
            buttonBorderLayer?.path = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex).path(in: CGRect(origin: .zero, size: buttonRect.size))
        }

        // rippleLayer 充满整个容器
        rippleLayer?.frame = bounds
        rippleLayer?.path = shape.path(in: bounds)

        // 更新按钮外边框位置与路径
        if let outline = buttonOutlineLayer, let btn = button {
            outline.frame = btn.frame
            outline.path = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex).path(in: CGRect(origin: .zero, size: btn.bounds.size))
        }

        // 更新特效边缘为配置形状并对齐按钮
        if let edge = effectEdgeLayer, let btn = button {
            edge.frame = btn.frame
            edge.path = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex).path(in: edge.bounds)
        }

        // 重新设置调试覆盖区域（仅在 DEBUG 下启用）
        setupDebugOverlay()
        updateDebugOverlay()
    }
}
@MainActor
final class GlowWindowManager {
    static let shared = GlowWindowManager()
    private var windows: [NSWindow] = []
    
    private init() {}
    
    func addWindow(_ window: NSWindow) {
        windows.append(window)
        
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            if let closedWindow = notification.object as? NSWindow {
                Task { @MainActor in
                    self.printWindowsCount() // avoid unused warning workarounds if any, or just modify directly
                    self.windows.removeAll { $0 === closedWindow }
                }
            }
        }
    }
    
    func printWindowsCount() {
        // Helper to avoid "property accessed" warning if strictly checked, though removeAll is mutation.
        // actually direct mutation in Task {@MainActor} is fine.
    }
}
