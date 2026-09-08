import Cocoa
import SwiftUI

class ColorListWindow: NSPanel {
    static let shared = ColorListWindow()
    
    private init() {
        let contentView = ColorListView()
        let hostingView = NSHostingView(rootView: contentView)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isMovableByWindowBackground = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.becomesKeyOnlyIfNeeded = false
        self.isOpaque = false
        self.contentView = hostingView
        
        // 监听窗口失去焦点
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: self)
    }
    
    @objc private func windowDidResignKey() {
        self.orderOut(nil)
    }
    
    func show(near rect: NSRect) {
        // 计算显示位置，默认显示在传入矩形的左侧或右侧
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        var x = rect.maxX + 10
        if x + frame.width > screenFrame.maxX {
            x = rect.minX - frame.width - 10
        }
        
        var y = rect.midY - frame.height / 2
        y = max(screenFrame.minY, min(y, screenFrame.maxY - frame.height))
        
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
