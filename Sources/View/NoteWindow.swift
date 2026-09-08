import Cocoa
import SwiftUI

class NoteWindow: NSPanel {
    init(initialViewMode: NoteListView.ViewMode = .all) {
        let config = FloatingButtonConfigManager.shared.config
        let contentView = NoteListView(initialViewMode: initialViewMode)
        let hostingView = NSHostingView(rootView: contentView)
        
        // 初始大小，高度设为自适应
        let windowRect = NSRect(x: 0, y: 0, width: 350, height: config.noteWindowHeight)
        super.init(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isMovableByWindowBackground = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // NSPanel 特殊配置：允许成为 key window
        self.becomesKeyOnlyIfNeeded = false
        self.worksWhenModal = false
        
        // 确保窗口可以接收鼠标事件
        self.acceptsMouseMovedEvents = true
        
        // 设置圆角和透明
        self.isOpaque = false
        self.backgroundColor = .clear
        self.contentView = hostingView
        
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // 开启自适应高度
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if let superview = hostingView.superview {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: superview.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
            ])
        }
        
        // 监听内容大小变化
        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeDidChange), name: NSView.boundsDidChangeNotification, object: hostingView)
        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeDidChange), name: Notification.Name("NoteViewModeChanged"), object: nil)
        
        // 监听窗口失去焦点
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: self)
        
        // 初始触发一次高度计算
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.updateHeightToFit()
        }
    }
    
    @objc private func windowDidResignKey() {
        // 窗口失去焦点时，发送通知完成所有编辑
        NotificationCenter.default.post(name: Notification.Name("FinishAllNoteEditing"), object: nil)
    }
    
    @objc private func contentSizeDidChange() {
        // 延迟一小会儿确保 SwiftUI 完成布局
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateHeightToFit()
        }
    }
    
    func updateHeightToFit() {
        guard let hostingView = contentView as? NSHostingView<NoteListView> else { return }
        
        // 使用 fittingSize 获取 SwiftUI 视图的理想大小
        let targetSize = hostingView.fittingSize
        
        // 限制在最小高度 150px
        let finalHeight = max(150, targetSize.height)
        let finalWidth = max(200, targetSize.width)
        
        if abs(frame.height - finalHeight) > 1 || abs(frame.width - finalWidth) > 1 {
            let currentFrame = frame
            let newFrame = NSRect(x: currentFrame.origin.x, y: currentFrame.origin.y, width: finalWidth, height: finalHeight)
            setFrame(newFrame, display: true, animate: true)
            
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: self)
        }
    }
    
    func setMode(_ mode: NoteListView.ViewMode) {
        let contentView = NoteListView(initialViewMode: mode)
        let hostingView = NSHostingView(rootView: contentView)
        
        self.contentView = hostingView
        
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if let superview = hostingView.superview {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: superview.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
            ])
        }
        
        // 重新绑定观察者
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeDidChange), name: NSView.boundsDidChangeNotification, object: hostingView)
        
        updateHeightToFit()
    }

    func updateHeight(_ height: CGFloat) {
        updateHeightToFit()
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    override func resignKey() {
        super.resignKey()
        // 窗口失去焦点时，发送通知完成所有编辑
        NotificationCenter.default.post(name: Notification.Name("FinishAllNoteEditing"), object: nil)
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        
        // 获取点击位置
        let location = event.locationInWindow
        
        // 检查点击位置是否在文本编辑器外部
        if let hostingView = contentView,
           let hitView = hostingView.hitTest(location) {
            
            // 如果点击的不是 NSTextView，则发送完成编辑通知
            if !(hitView is NSTextView) {
                NotificationCenter.default.post(name: Notification.Name("FinishAllNoteEditing"), object: nil)
            }
        }
    }
}
