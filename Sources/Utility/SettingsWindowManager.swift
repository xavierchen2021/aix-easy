import SwiftUI
import AppKit

@MainActor
class SettingsWindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()
    
    private var settingsWindow: NSWindow?
    
    private override init() {
        super.init()
    }
    
    func showSettings() {
        if let existingWindow = settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "AIX 设置"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        // 设置窗口外观
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // 设置最小尺寸
        window.minSize = NSSize(width: 600, height: 500)
        window.delegate = self
        
        self.settingsWindow = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        print("🪟 设置窗口即将关闭")
        ReminderManager.shared.handleSettingsClosed()
        settingsWindow = nil
    }
    
    func closeSettings() {
        settingsWindow?.close()
        // windowWillClose will be called and handle the cleanup
    }
}
