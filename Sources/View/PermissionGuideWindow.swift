import Cocoa
import SwiftUI

/// 辅助功能权限引导窗口
class PermissionGuideWindow: NSWindow {
    static let shared = PermissionGuideWindow()
    
    private init() {
        let contentView = PermissionGuideView {
            PermissionGuideWindow.shared.orderOut(nil)
        }
        let hostingView = NSHostingView(rootView: contentView)
        
        let windowRect = NSRect(x: 0, y: 0, width: 480, height: 460)
        super.init(
            contentRect: windowRect,
            // 不包含 .closable，使其不可通过按钮关闭
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.title = "权限申请"
        self.isMovableByWindowBackground = true
        self.backgroundColor = .windowBackgroundColor
        self.level = .floating // 始终置顶
        self.center()
        
        self.contentView = hostingView
        
        // 允许在设置窗口后面显示
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct PermissionGuideView: View {
    var onDismiss: () -> Void
    
    @State private var hasAccessibilityPermission = false
    @State private var hasScreenRecordingPermission = false
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
                .padding(.top, 15)
            
            VStack(spacing: 10) {
                Text(L10n.tr("permission.title"))
                    .font(.system(size: 20, weight: .bold))
            }
            
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    HStack {
                        Text(L10n.tr("permission.accessibility"))
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(hasAccessibilityPermission ? "已授权" : "未授权")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(hasAccessibilityPermission ? .green : .red)
                    }
                    
                    Text(L10n.tr("permission.accessibilityDesc"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button(action: {
                        InputMonitor.promptForAccessibilityPermission()
                    }) {
                        Text(L10n.tr("permission.openSettings"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 200, height: 36)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Text(L10n.tr("permission.accessibilityPath"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                VStack(spacing: 10) {
                    HStack {
                        Text(L10n.tr("permission.screenRecording"))
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(hasScreenRecordingPermission ? "已授权" : "未授权")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(hasScreenRecordingPermission ? .green : .red)
                    }
                    
                    Text(L10n.tr("permission.screenRecordingDesc"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button(action: {
                        ScreenRecordingPermission.openSystemSettings()
                    }) {
                        Text(L10n.tr("permission.openSettings"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 200, height: 36)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Text(L10n.tr("permission.screenRecordingPath"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 15)
        }
        .padding(20)
        .frame(width: 480, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(timer) { _ in
            checkPermission()
        }
        .onAppear {
            checkPermission()
        }
    }
    
    private func checkPermission() {
        let accessibilityGranted = AXIsProcessTrustedWithOptions(nil)
        let screenGranted = ScreenRecordingPermission.hasPermission()
        hasAccessibilityPermission = accessibilityGranted
        hasScreenRecordingPermission = screenGranted

        if accessibilityGranted && screenGranted {
            print("✅ PermissionGuideView: 检测到权限已获得，正在关闭引导窗口并启动服务")
            // 延迟一小会儿，让用户看到“已获得”状态（可选）或者直接开始
            Task { @MainActor in
                ReminderManager.shared.refreshState()
                onDismiss()
            }
        }
    }
}
