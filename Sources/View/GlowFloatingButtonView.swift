import Cocoa

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceIn)
        image.unlockFocus()
        return image
    }
}

// 一个新的悬浮按钮实现，使用完全不同的层级结构以确保外发光可见
class GlowFloatingButtonView: NSView {
    
    // 配置
    var buttonIndex: Int = 0 {
        didSet {
            refreshConfig()
        }
    }    
    private var containerLayer: CALayer!    // 最外层容器
    private var glowLayer: CALayer!         // 发光层
    private var buttonLayer: CALayer!       // 按钮本体层
    private var iconLayer: CALayer!         // 图标层
    private var isHovered = false
    
    // 拖拽相关变量
    private var isDragging = false
    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private let dragThreshold: CGFloat = 5.0
    
    // 单击事件回调
    var onClick: (() -> Void)?
    
    static let floatingButtonClickedNotification = Notification.Name("floatingButtonClicked")
    static let configChangedNotification = Notification.Name("floatingButtonConfigChanged")
    static let visibilityChangedNotification = Notification.Name("floatingButtonVisibilityChanged")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayerStructure()
        setupNotificationObservers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayerStructure()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChanged),
            name: GlowFloatingButtonView.configChangedNotification,
            object: nil
        )
    }
    
    @objc private func handleConfigChanged() {
        refreshConfig()
        updateBreathingAnimation()
        updateGlowIntensity()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupLayerStructure() {
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        
        let configManager = FloatingButtonConfigManager.shared
        let config = configManager.config
        let size = configManager.getButtonSize(index: buttonIndex)
        let colorScheme = configManager.getButtonColorScheme(index: buttonIndex)
        let shape = configManager.getButtonShape(index: buttonIndex)
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        // 根据形状计算按钮尺寸
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
        
        // 1. 发光层 (Glow) - 位于最底层
        glowLayer = CALayer()
        glowLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        glowLayer.position = center
        
        // 对于圆形设置 cornerRadius 辅助裁剪，非圆形（或已由 path 定义）则谨慎设置
        if shape == .circle {
            glowLayer.cornerRadius = height / 2
        } else {
            glowLayer.cornerRadius = 0
        }
        
        let baseShadowRadius = size * 0.08
        glowLayer.shadowColor = colorScheme.endColor
        glowLayer.shadowOpacity = Float(config.glowIntensity)
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = baseShadowRadius
        
        // 根据形状设置阴影路径
        let glowPath = shape.path(in: glowLayer.bounds)
        glowLayer.shadowPath = glowPath
        
        layer?.addSublayer(glowLayer)
        
        // 添加呼吸动画
        updateBreathingAnimation()
        
        // 2. 按钮层 (Button Body)
        buttonLayer = CALayer()
        buttonLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        buttonLayer.position = center
        
        // 渐变色
        let gradient = CAGradientLayer()
        gradient.frame = buttonLayer.bounds
        
        // 使用形状遮罩
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = shape.path(in: buttonLayer.bounds)
        shapeLayer.frame = buttonLayer.bounds
        gradient.mask = shapeLayer
        
        gradient.colors = [
            colorScheme.startColor,
            colorScheme.endColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        
        buttonLayer.addSublayer(gradient)
        layer?.addSublayer(buttonLayer)
        
        // 3. 图标层
        iconLayer = CALayer()
        iconLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        iconLayer.position = center
        
        // 根据配置显示图标或文字
        if let action = config.buttonActions[buttonIndex] {
            if config.displayMode == FloatingButtonConfig.DisplayMode.textOnly {
                // 显示文字
                let textLayer = CATextLayer()
                textLayer.string = action.localizedName
                textLayer.fontSize = size * 0.3
                textLayer.alignmentMode = .center
                textLayer.foregroundColor = colorScheme.contentTintColor
                textLayer.frame = iconLayer.bounds
                iconLayer.addSublayer(textLayer)
            } else {
                // 显示图标
                let iconName = config.customIcons[buttonIndex] ?? action.iconName
                if let iconName = iconName {
                    let iconConfig = NSImage.SymbolConfiguration(pointSize: size * 0.4, weight: .medium)
                    if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(iconConfig) {
                        let iconImageLayer = CALayer()
                        iconImageLayer.frame = CGRect(x: (width - size * 0.4) / 2, y: (height - size * 0.4) / 2, width: size * 0.4, height: size * 0.4)
                        
                        // 根据背景色深浅设置图标颜色
                        let iconColor: NSColor
                        if colorScheme == .pureBlack {
                            iconColor = NSColor.white
                        } else {
                            iconColor = NSColor(cgColor: colorScheme.contentTintColor) ?? NSColor.white
                        }
                        
                        let tintedIcon = icon.tinted(with: iconColor)
                        iconImageLayer.contents = tintedIcon
                        iconImageLayer.contentsGravity = .resizeAspect
                        iconLayer.addSublayer(iconImageLayer)
                    }
                }
            }
        }
        
        layer?.addSublayer(iconLayer)
    }
    
    private func setupTracking() {
        guard let buttonLayer = buttonLayer else { return }
        
        let buttonSize = buttonLayer.bounds.size
        let buttonPosition = buttonLayer.position
        
        // trackingArea 应该覆盖按钮及其发光感应区域，尽量紧凑
        let configManager = FloatingButtonConfigManager.shared
        let size = configManager.getButtonSize(index: buttonIndex)
        let glowPadding = size * 0.2
        
        let buttonRect = CGRect(
            x: buttonPosition.x - buttonSize.width / 2 - glowPadding,
            y: buttonPosition.y - buttonSize.height / 2 - glowPadding,
            width: buttonSize.width + glowPadding * 2,
            height: buttonSize.height + glowPadding * 2
        )
        
        trackingAreas.forEach { removeTrackingArea($0) }
        
        let area = NSTrackingArea(rect: buttonRect, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
    }
    
    override func layout() {
        super.layout()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        glowLayer?.position = center
        buttonLayer?.position = center
        iconLayer?.position = center
        
        setupTracking()
    }
    
    override func mouseEntered(with event: NSEvent) {
    }
    
    override func mouseExited(with event: NSEvent) {
    }
    
    override func mouseDown(with event: NSEvent) {
        // 记录初始位置，用于拖拽检测
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowOrigin = window?.frame.origin ?? .zero
        isDragging = false
        
        // 通知分组拖拽开始
        NotificationCenter.default.post(name: FloatingWindow.dragStartNotification, object: window)
        
        // 点击反馈 - 快速收缩
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.95
        scale.duration = 0.4
        scale.damping = 15
        scale.stiffness = 300
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false
        
        buttonLayer.add(scale, forKey: "clickDown")
        glowLayer.add(scale, forKey: "clickDown")
    }
    
    override func mouseDragged(with event: NSEvent) {
        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - initialMouseLocation.x
        let deltaY = currentMouseLocation.y - initialMouseLocation.y
        
        // 检测是否超过拖拽阈值
        let dragDistance = sqrt(deltaX * deltaX + deltaY * deltaY)
        if dragDistance > dragThreshold {
            isDragging = true
        }
        
        guard isDragging, let window = window else { return }
        
        let newOrigin = NSPoint(
            x: initialWindowOrigin.x + deltaX,
            y: initialWindowOrigin.y + deltaY
        )
        
        window.setFrameOrigin(newOrigin)
        
        // 通知同组悬浮球跟随移动
        NotificationCenter.default.post(
            name: FloatingWindow.dragNotification,
            object: window,
            userInfo: ["deltaX": deltaX, "deltaY": deltaY]
        )
    }
    
    override func mouseUp(with event: NSEvent) {
        // 如果是拖拽操作，不触发点击事件
        if isDragging {
            isDragging = false
            
            // 恢复缩放到正常大小
            let scale = CASpringAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.95
            scale.toValue = 1.0
            scale.duration = scale.settlingDuration
            scale.damping = 10
            scale.stiffness = 200
            scale.fillMode = .forwards
            scale.isRemovedOnCompletion = false
            buttonLayer.add(scale, forKey: "clickUp")
            glowLayer.add(scale, forKey: "clickUp")
            
            // 通知分组拖拽结束
            NotificationCenter.default.post(name: FloatingWindow.dragEndNotification, object: window)
            
            // 发送窗口移动通知
            NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: window)
            return
        }
        
        // 通知分组拖拽结束（非拖拽点击也要结束）
        NotificationCenter.default.post(name: FloatingWindow.dragEndNotification, object: window)
        
        // 松开 - 弹回正常状态
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.95
        scale.toValue = 1.0
        scale.duration = scale.settlingDuration
        scale.damping = 10
        scale.stiffness = 200
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false
        
        buttonLayer.add(scale, forKey: "clickUp")
        glowLayer.add(scale, forKey: "clickUp")
        
        // 只有当鼠标还在视图内时才触发点击
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onClick?()
            // 发送点击通知
            NotificationCenter.default.post(name: GlowFloatingButtonView.floatingButtonClickedNotification, object: self)
        }
    }
    
    func refreshConfig() {
        // 移除旧的 layer
        glowLayer?.removeFromSuperlayer()
        buttonLayer?.removeFromSuperlayer()
        iconLayer?.removeFromSuperlayer()
        
        // 重新创建 layer 结构
        setupLayerStructure()
    }
    
    private func updateBreathingAnimation() {
        guard let glowLayer = glowLayer else { return }
        
        let configManager = FloatingButtonConfigManager.shared
        let config = configManager.config
        let size = configManager.getButtonSize(index: buttonIndex)
        let baseShadowRadius = size * 0.08
        let maxShadowRadius = size * 0.15
        
        if config.enableBreathingEffect {
            let breathAnim = CABasicAnimation(keyPath: "shadowRadius")
            breathAnim.fromValue = baseShadowRadius
            breathAnim.toValue = maxShadowRadius
            breathAnim.duration = 1.0 / config.breathingSpeed
            breathAnim.autoreverses = true
            breathAnim.repeatCount = .infinity
            breathAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glowLayer.add(breathAnim, forKey: "breathGlow")
        } else {
            glowLayer.removeAnimation(forKey: "breathGlow")
            glowLayer.shadowRadius = baseShadowRadius
        }
    }
    
    private func updateGlowIntensity() {
        guard let glowLayer = glowLayer else { return }
        let config = FloatingButtonConfigManager.shared.config
        glowLayer.shadowOpacity = Float(config.glowIntensity)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: L10n.tr("button.menu"))
        
        let config = FloatingButtonConfigManager.shared.config
        
        for action in FloatingButtonConfig.ButtonAction.allCases where action != .plugin && action != .showReminder && action != .showCompletedNotes {
            // 如果是控制窗口模式，且没有辅助功能权限，则不显示该选项
            if action == .toggleWindow && !InputMonitor.hasAccessibilityPermission() {
                continue
            }
            
            let actionItem = NSMenuItem(title: action.localizedName, action: #selector(actionItemClicked(_:)), keyEquivalent: "")
            actionItem.target = self
            actionItem.state = (config.buttonActions[buttonIndex] == action) ? .on : .off
            actionItem.tag = FloatingButtonConfig.ButtonAction.allCases.firstIndex(of: action)!
            menu.addItem(actionItem)
        }
        
        if config.buttonActions[buttonIndex] == .toggleWindow && InputMonitor.hasAccessibilityPermission() {
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: L10n.tr("button.rebindWindow"), action: #selector(clearWindowBindingFromMenu(_:)), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        if let group = FloatingButtonConfigManager.shared.getGroup(for: buttonIndex), group.memberIndices.count > 1 {
            menu.addItem(NSMenuItem.separator())
            let arrangeGroupItem = NSMenuItem(title: L10n.tr("button.arrangeGroup"), action: #selector(arrangeGroupFromMenu(_:)), keyEquivalent: "")
            arrangeGroupItem.target = self
            menu.addItem(arrangeGroupItem)

            let configMgr = FloatingButtonConfigManager.shared
            let moveForwardItem = NSMenuItem(title: L10n.tr("button.moveForward"), action: configMgr.canMoveForward(buttonIndex: buttonIndex) ? #selector(moveForwardInGroup(_:)) : nil, keyEquivalent: "")
            moveForwardItem.target = self
            if !configMgr.canMoveForward(buttonIndex: buttonIndex) {
                moveForwardItem.isEnabled = false
            }
            menu.addItem(moveForwardItem)

            let moveBackwardItem = NSMenuItem(title: L10n.tr("button.moveBackward"), action: configMgr.canMoveBackward(buttonIndex: buttonIndex) ? #selector(moveBackwardInGroup(_:)) : nil, keyEquivalent: "")
            moveBackwardItem.target = self
            if !configMgr.canMoveBackward(buttonIndex: buttonIndex) {
                moveBackwardItem.isEnabled = false
            }
            menu.addItem(moveBackwardItem)
        }

        if config.buttonActions[buttonIndex] == .executeHotkey {
            menu.addItem(NSMenuItem.separator())
            let currentHotkey = config.buttonHotkeys[buttonIndex] ?? ""
            let bindTitle = currentHotkey.isEmpty ? "绑定快捷键" : "修改快捷键"
            let bindItem = NSMenuItem(title: bindTitle, action: #selector(editHotkeyBindingFromMenu(_:)), keyEquivalent: "")
            bindItem.target = self
            menu.addItem(bindItem)

            if !currentHotkey.isEmpty {
                let clearHotkeyItem = NSMenuItem(title: L10n.tr("button.clearHotkey"), action: #selector(clearHotkeyBindingFromMenu(_:)), keyEquivalent: "")
                clearHotkeyItem.target = self
                menu.addItem(clearHotkeyItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        let customizeItem = NSMenuItem(title: L10n.tr("button.customize2"), action: #selector(openCustomizationPanel), keyEquivalent: "")
        customizeItem.target = self
        menu.addItem(customizeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        if config.buttonCount > 1 {
            let deleteItem = NSMenuItem(title: L10n.tr("button.deleteButton"), action: #selector(deleteFloatingButton(_:)), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        let closeItem = NSMenuItem(title: L10n.tr("common.hide"), action: #selector(closeSelf), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    @objc func closeSelf() {
        FloatingButtonConfigManager.shared.recordUserHiddenButton(index: buttonIndex)
        self.window?.orderOut(nil)
        NotificationCenter.default.post(name: GlowFloatingButtonView.visibilityChangedNotification, object: nil)
    }
    
    @objc private func actionItemClicked(_ sender: NSMenuItem) {
        let actionIndex = sender.tag
        let action = FloatingButtonConfig.ButtonAction.allCases[actionIndex]
        
        FloatingButtonConfigManager.shared.updateButtonAction(index: buttonIndex, action: action)
        
        NotificationCenter.default.post(name: GlowFloatingButtonView.configChangedNotification, object: nil)
    }
    
    @objc private func clearWindowBindingFromMenu(_ sender: NSMenuItem) {
        FloatingButtonConfigManager.shared.unbindWindow(index: buttonIndex)
        
        // 立即进入窗口选择蒙版
        WindowManager.shared.startWindowSelection(for: buttonIndex)
        
        NotificationCenter.default.post(name: GlowFloatingButtonView.configChangedNotification, object: nil)
    }

    @objc private func arrangeGroupFromMenu(_ sender: NSMenuItem) {
        NotificationCenter.default.post(name: Notification.Name("arrangeGroupMembers"), object: buttonIndex)
    }

    @objc private func moveForwardInGroup(_ sender: NSMenuItem) {
        FloatingButtonConfigManager.shared.moveButtonInGroup(buttonIndex: buttonIndex, forward: true)
    }

    @objc private func moveBackwardInGroup(_ sender: NSMenuItem) {
        FloatingButtonConfigManager.shared.moveButtonInGroup(buttonIndex: buttonIndex, forward: false)
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
        NotificationCenter.default.post(name: GlowFloatingButtonView.configChangedNotification, object: nil)
    }
    
    @objc private func deleteFloatingButton(_ sender: NSMenuItem) {
        let config = FloatingButtonConfigManager.shared.config
        
        if config.buttonCount <= 1 {
            return
        }
        
        NotificationCenter.default.post(name: Notification.Name("deleteFloatingButton"), object: buttonIndex)
    }
    
    @objc private func openCustomizationPanel() {
        Logger.shared.log("🎨 openCustomizationPanel: buttonIndex=\(buttonIndex)")

        let windowRect = NSRect(x: 0, y: 0, width: 350, height: 480)
        let customizationWindow = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        customizationWindow.title = "悬浮球 \(buttonIndex + 1) 个性化设置"
        customizationWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        customizationWindow.isReleasedWhenClosed = false

        let contentView = NSView(frame: windowRect)
        customizationWindow.contentView = contentView

        let configManager = FloatingButtonConfigManager.shared
        let currentCustomization = configManager.config.buttonCustomizations[buttonIndex] ?? FloatingButtonConfig.ButtonCustomization()

        // 大小设置
        let sizeLabel = NSTextField(labelWithString: "大小:")
        sizeLabel.frame = NSRect(x: 20, y: 440, width: 60, height: 24)
        contentView.addSubview(sizeLabel)

        let sizeSlider = NSSlider(
            value: Double(currentCustomization.size ?? configManager.config.size),
            minValue: Double(FloatingButtonConfig.minSize),
            maxValue: Double(FloatingButtonConfig.maxSize),
            target: self,
            action: #selector(customSizeChanged(_:))
        )
        sizeSlider.frame = NSRect(x: 90, y: 440, width: 180, height: 24)
        sizeSlider.tag = 1000 + buttonIndex
        contentView.addSubview(sizeSlider)

        let sizeValueLabel = NSTextField(labelWithString: "\(Int(currentCustomization.size ?? configManager.config.size))px")
        sizeValueLabel.frame = NSRect(x: 280, y: 440, width: 60, height: 24)
        sizeValueLabel.tag = 4000 + buttonIndex
        contentView.addSubview(sizeValueLabel)

        // 颜色主题设置
        let colorLabel = NSTextField(labelWithString: "颜色主题:")
        colorLabel.frame = NSRect(x: 20, y: 390, width: 80, height: 24)
        contentView.addSubview(colorLabel)

        let colorPopup = NSPopUpButton(frame: NSRect(x: 110, y: 390, width: 200, height: 24))
        colorPopup.tag = 2000 + buttonIndex // 专属 Tag
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
        shapeLabel.frame = NSRect(x: 20, y: 350, width: 80, height: 24)
        contentView.addSubview(shapeLabel)

        let shapePopup = NSPopUpButton(frame: NSRect(x: 110, y: 350, width: 200, height: 24))
        shapePopup.tag = 3000 + buttonIndex // 专属 Tag
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

        // 分组设置
        let groupLabel = NSTextField(labelWithString: "分组:")
        groupLabel.frame = NSRect(x: 20, y: 310, width: 80, height: 24)
        contentView.addSubview(groupLabel)

        let groupPopup = NSPopUpButton(frame: NSRect(x: 110, y: 310, width: 200, height: 24))
        groupPopup.addItem(withTitle: L10n.tr("button.noGroup"))
        let currentGroup = configManager.getGroup(for: buttonIndex)
        for group in configManager.config.buttonGroups {
            let memberNames = group.memberIndices.map { "球\($0 + 1)" }.joined(separator: ",")
            groupPopup.addItem(withTitle: "\(group.name) (\(memberNames))")
            if currentGroup?.id == group.id {
                groupPopup.selectItem(at: groupPopup.numberOfItems - 1)
            }
        }
        groupPopup.tag = 5000 + buttonIndex
        groupPopup.target = self
        groupPopup.action = #selector(groupSelectionChanged(_:))
        contentView.addSubview(groupPopup)

        // 新建分组输入框和按钮
        let newGroupField = NSTextField(frame: NSRect(x: 110, y: 270, width: 130, height: 24))
        newGroupField.placeholderString = "输入分组名称"
        newGroupField.tag = 7000 + buttonIndex
        contentView.addSubview(newGroupField)

        let newGroupButton = NSButton(title: L10n.tr("button.newGroup"), target: self, action: #selector(createNewGroupClicked(_:)))
        newGroupButton.frame = NSRect(x: 250, y: 270, width: 60, height: 24)
        newGroupButton.tag = 8000 + buttonIndex
        contentView.addSubview(newGroupButton)

        // 分组排列方式
        let layoutLabel = NSTextField(labelWithString: "排列方式:")
        layoutLabel.frame = NSRect(x: 20, y: 230, width: 80, height: 24)
        contentView.addSubview(layoutLabel)

        let layoutPopup = NSPopUpButton(frame: NSRect(x: 110, y: 230, width: 200, height: 24))
        for layout in FloatingButtonConfig.GroupLayout.allCases {
            layoutPopup.addItem(withTitle: layout.localizedName)
        }
        if let currentLayout = currentGroup?.layout,
           let idx = FloatingButtonConfig.GroupLayout.allCases.firstIndex(of: currentLayout) {
            layoutPopup.selectItem(at: idx)
        }
        layoutPopup.isEnabled = currentGroup != nil
        layoutPopup.tag = 6000 + buttonIndex
        contentView.addSubview(layoutPopup)

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
        
        // 临时切换激活策略以允许键盘输入
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        customizationWindow.makeKeyAndOrderFront(nil)
        
        // 窗口关闭时恢复激活策略
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: customizationWindow, queue: .main) { _ in
            MainActor.assumeIsolated {
                _ = NSApp.setActivationPolicy(.prohibited)
            }
        }
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

    @objc private func groupSelectionChanged(_ sender: NSPopUpButton) {
        let index = sender.tag - 5000
        guard let window = sender.window, let contentView = window.contentView else { return }
        
        let configManager = FloatingButtonConfigManager.shared
        let isGroupSelected = sender.indexOfSelectedItem > 0
        
        // 启用/禁用排列方式下拉框
        if let layoutPopup = contentView.viewWithTag(6000 + index) as? NSPopUpButton {
            layoutPopup.isEnabled = isGroupSelected
            
            // 如果选择了分组，同步该分组的已有属性
            if isGroupSelected {
                let groupIndex = sender.indexOfSelectedItem - 1
                if groupIndex < configManager.config.buttonGroups.count {
                    let group = configManager.config.buttonGroups[groupIndex]
                    
                    // 1. 同步排列方式
                    if let layoutIdx = FloatingButtonConfig.GroupLayout.allCases.firstIndex(of: group.layout) {
                        layoutPopup.selectItem(at: layoutIdx)
                    }
                    
                    // 2. 如果分组内已有成员，同步其尺寸和形状
                    if let firstMemberIndex = group.memberIndices.first(where: { $0 != index }) {
                        let memberSize = configManager.getButtonSize(index: firstMemberIndex)
                        let memberShape = configManager.getButtonShape(index: firstMemberIndex)
                        
                        // 更新大小滑块
                        if let sizeSlider = contentView.viewWithTag(1000 + index) as? NSSlider {
                            sizeSlider.doubleValue = Double(memberSize)
                            // 同时更新数值标签
                            if let valueLabel = contentView.viewWithTag(4000 + index) as? NSTextField {
                                valueLabel.stringValue = "\(Int(memberSize))px"
                            }
                        }
                        
                        // 更新形状下拉框
                        if let shapePopup = contentView.viewWithTag(3000 + index) as? NSPopUpButton {
                            if let shapeIdx = FloatingButtonConfig.ButtonShape.allCases.firstIndex(of: memberShape) {
                                shapePopup.selectItem(at: shapeIdx)
                            }
                        }
                    }
                }
            }
        }
    }

    @objc private func createNewGroupClicked(_ sender: NSButton) {
        let index = sender.tag - 8000
        guard let window = sender.window, let contentView = window.contentView else { return }
        guard let nameField = contentView.viewWithTag(7000 + index) as? NSTextField else { return }
        
        let groupName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupName.isEmpty else { return }
        
        let configManager = FloatingButtonConfigManager.shared
        let newGroup = configManager.createGroup(name: groupName, memberIndices: [index])
        
        // 重建分组下拉框
        if let groupPopup = contentView.viewWithTag(5000 + index) as? NSPopUpButton {
            groupPopup.removeAllItems()
            groupPopup.addItem(withTitle: "不分组")
            for group in configManager.config.buttonGroups {
                let memberNames = group.memberIndices.map { "球\($0 + 1)" }.joined(separator: ",")
                groupPopup.addItem(withTitle: "\(group.name) (\(memberNames))")
                if group.id == newGroup.id {
                    groupPopup.selectItem(at: groupPopup.numberOfItems - 1)
                }
            }
        }
        
        // 启用排列方式
        if let layoutPopup = contentView.viewWithTag(6000 + index) as? NSPopUpButton {
            layoutPopup.isEnabled = true
        }
        
        // 清空输入框
        nameField.stringValue = ""
    }

    @objc private func resetCustomization(_ sender: NSButton) {
        let index = sender.tag
        FloatingButtonConfigManager.shared.updateButtonCustomization(index: index, customization: FloatingButtonConfig.ButtonCustomization())
        sender.window?.close()
        NotificationCenter.default.post(name: GlowFloatingButtonView.configChangedNotification, object: nil)
    }

    @objc private func applyCustomization(_ sender: NSButton) {
        let index = sender.tag
        guard let window = sender.window, let contentView = window.contentView else { return }
        
        // 重要：先获取现有的定制化设置，避免覆盖其他未修改的属性
        let configManager = FloatingButtonConfigManager.shared
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
                customization.colorScheme = nil // 恢复全局设置
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

        // 处理分组设置
        if let groupPopup = contentView.viewWithTag(5000 + index) as? NSPopUpButton {
            let selectedIndex = groupPopup.indexOfSelectedItem
            let existingGroups = configManager.config.buttonGroups
            
            if selectedIndex == 0 {
                // "不分组" - 从当前分组移除
                configManager.removeFromGroup(buttonIndex: index)
            } else {
                // 加入已有分组（包括刚通过"新建"按钮创建的分组）
                let groupIndex = selectedIndex - 1
                if groupIndex < existingGroups.count {
                    // 检查是否已在该分组中
                    let targetGroup = existingGroups[groupIndex]
                    if !targetGroup.memberIndices.contains(index) {
                        configManager.addToGroup(buttonIndex: index, groupId: targetGroup.id)
                    }
                    // 更新排列方式
                    if let layoutPopup = contentView.viewWithTag(6000 + index) as? NSPopUpButton {
                        let layoutIndex = layoutPopup.indexOfSelectedItem
                        let layout = FloatingButtonConfig.GroupLayout.allCases[layoutIndex]
                        configManager.updateGroupLayout(groupId: targetGroup.id, layout: layout)
                    }
                }
            }
        }

        // 自动排列分组成员
        NotificationCenter.default.post(name: Notification.Name("arrangeGroupMembers"), object: index)

        window.close()
        NotificationCenter.default.post(name: GlowFloatingButtonView.configChangedNotification, object: nil)
    }
}
