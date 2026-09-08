import Cocoa

class FloatingWindow: NSPanel {
    private var isDragging = false
    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var maskLayer: CAShapeLayer!

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setupWindow()
    }

    convenience init(contentView: NSView) {
        let configManager = FloatingButtonConfigManager.shared
        let index = (contentView as? GlowFloatingButtonView)?.buttonIndex ?? 
                    (contentView as? FloatingButtonView)?.buttonIndex ?? 0
        let size = configManager.getButtonSize(index: index)
        
        // 容器大小 = 按钮大小 + padding * 2，padding 足够容纳发光效果
        let padding: CGFloat = size * 0.25
        
        let maxDim: CGFloat
        let shape = configManager.getButtonShape(index: index)
        switch shape {
        case .circle, .roundedSquare:
            maxDim = size
        case .capsule:
            maxDim = max(size, size * 1.4)
        }

        let contentRect = NSRect(x: 0, y: 0, width: maxDim + padding * 2, height: maxDim + padding * 2)
        self.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView.frame = NSRect(origin: .zero, size: contentRect.size)
        self.contentView = contentView
    }

    private func setupWindow() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false

        // 设置圆角遮罩
        updateMask(for: frame.size)

        // 确保窗口可以接收鼠标事件
        acceptsMouseMovedEvents = true
    }

    func updateMask(for size: CGSize) {
        // 移除所有遮罩逻辑，允许内容溢出（如外发光）
        contentView?.wantsLayer = true
        contentView?.layer?.mask = nil
        contentView?.layer?.masksToBounds = false
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func updateSize(_ size: CGFloat) {
        // 根据按钮尺寸来计算窗口的真实宽度与高度（适配圆形或胶囊）
        // 增加 padding 使其随 size 变化，确保外发光不被裁剪（半径最大 size * 0.15，padding 取 size * 0.25 足够容纳）
        let padding: CGFloat = size * 0.25
        let buttonSize = size
        var height: CGFloat
        var width: CGFloat
        
        let buttonIndex: Int
        if let btnView = contentView as? FloatingButtonView {
            buttonIndex = btnView.buttonIndex
        } else if let glowView = contentView as? GlowFloatingButtonView {
            buttonIndex = glowView.buttonIndex
        } else {
            buttonIndex = 0
        }
        
        let shape = FloatingButtonConfigManager.shared.getButtonShape(index: buttonIndex)
        switch shape {
        case .circle, .roundedSquare:
            height = buttonSize
            width = buttonSize
        case .capsule:
            height = max(18.0, buttonSize * 0.6)
            width = max(buttonSize, buttonSize * 1.4)
        }

        // 确保窗口是正方形，取最大边长
        let maxDimension = max(width, height)
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: maxDimension + padding * 2,
            height: maxDimension + padding * 2
        )
        setFrame(newFrame, display: true)

        // 更新遮罩以匹配新的窗口尺寸
        updateMask(for: CGSize(width: newFrame.width, height: newFrame.height))

        // 更新阴影
        hasShadow = false
    }

    static let dragNotification = Notification.Name("FloatingWindowDragged")
    static let dragStartNotification = Notification.Name("FloatingWindowDragStart")
    static let dragEndNotification = Notification.Name("FloatingWindowDragEnd")

    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowOrigin = frame.origin
        isDragging = true
        NotificationCenter.default.post(name: FloatingWindow.dragStartNotification, object: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }

        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - initialMouseLocation.x
        let deltaY = currentMouseLocation.y - initialMouseLocation.y

        let newOrigin = NSPoint(
            x: initialWindowOrigin.x + deltaX,
            y: initialWindowOrigin.y + deltaY
        )

        setFrameOrigin(newOrigin)

        // 通知同组悬浮球跟随移动
        NotificationCenter.default.post(
            name: FloatingWindow.dragNotification,
            object: self,
            userInfo: ["deltaX": deltaX, "deltaY": deltaY]
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        NotificationCenter.default.post(name: FloatingWindow.dragEndNotification, object: self)
    }

}
