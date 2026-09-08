import AppKit
import SwiftUI

// MARK: - 蒙版状态数据模型

@MainActor
final class ReminderOverlayState: ObservableObject {
    @Published var message: String
    @Published var remainingTime: String?

    init(message: String, remainingTime: String?) {
        self.message = message
        self.remainingTime = remainingTime
    }
}

// MARK: - 主控屏蒙版窗口

/// 主控屏幕蒙版窗口（包含倒计时与「稍后休息」控制按钮）
final class ReminderPrimaryOverlayWindow: NSWindow {
    private let state: ReminderOverlayState
    private let onDismissAction: () -> Void

    init(screen: NSScreen, state: ReminderOverlayState, onDismiss: @escaping () -> Void) {
        self.state = state
        self.onDismissAction = onDismiss

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        setupWindow(screen: screen)
        setupContentView()
    }

    private func setupWindow(screen: NSScreen) {
        isReleasedWhenClosed = false
        level = .screenSaver
        backgroundColor = NSColor.black.withAlphaComponent(0.85)
        isOpaque = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = false
        isMovable = false

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        setFrame(screen.frame, display: true)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
    }

    private func setupContentView() {
        let rootView = ReminderPrimaryOverlayView(state: state, onDismiss: onDismissAction)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = frame
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        // 屏蔽所有键盘按键（包括 ESC），确保只能通过点击「稍后休息」按钮或倒计时归零解除
    }
}

// MARK: - 副屏蒙版窗口

/// 副屏蒙版窗口（显示深色遮罩背景与「休息中」文字提示，无倒计时与按钮，拦截鼠标键盘）
final class ReminderSecondaryOverlayWindow: NSWindow {

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        setupWindow(screen: screen)
        setupContentView()
    }

    private func setupWindow(screen: NSScreen) {
        isReleasedWhenClosed = false
        level = .screenSaver
        backgroundColor = NSColor.black.withAlphaComponent(0.85)
        isOpaque = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = false
        isMovable = false

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        setFrame(screen.frame, display: true)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
    }

    private func setupContentView() {
        let rootView = ReminderSecondaryOverlayView()
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = frame
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    override var acceptsFirstResponder: Bool { false }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        // 屏蔽副屏所有按键事件
    }
}

// MARK: - 提醒蒙版控制器（多屏幕协同管理器）

/// 提醒休息蒙版窗口与多屏幕协同控制器
@MainActor
class ReminderOverlayWindow {
    var onContinue: (() -> Void)?
    var message: String {
        didSet {
            state.message = message
        }
    }
    var remainingTime: String? {
        didSet {
            state.remainingTime = remainingTime
        }
    }

    private let state: ReminderOverlayState
    private let onDismiss: () -> Void

    private var primaryWindow: ReminderPrimaryOverlayWindow?
    private var secondaryWindows: [ReminderSecondaryOverlayWindow] = []

    nonisolated(unsafe) private var keyDownMonitor: Any?
    nonisolated(unsafe) private var flagsChangedMonitor: Any?
    nonisolated(unsafe) private var scrollWheelMonitor: Any?
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    var isVisible: Bool {
        return (primaryWindow?.isVisible == true) || secondaryWindows.contains(where: { $0.isVisible })
    }

    init(message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        self.state = ReminderOverlayState(message: message, remainingTime: nil)

        setupWakeObserver()
        setupScreenObserver()
    }

    deinit {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsChangedMonitor { NSEvent.removeMonitor(m) }
        if let m = scrollWheelMonitor { NSEvent.removeMonitor(m) }
        if let o = wakeObserver { NotificationCenter.default.removeObserver(o) }
        if let s = screenObserver { NotificationCenter.default.removeObserver(s) }
    }

    // MARK: - Show / Dismiss / Close

    func show() {
        if isVisible {
            state.message = message
            state.remainingTime = remainingTime
            return
        }

        dismissWindows()

        state.message = message
        state.remainingTime = remainingTime

        // 确定当前鼠标光标所在的屏幕作为主控屏幕
        let mouseLoc = NSEvent.mouseLocation
        let allScreens = NSScreen.screens
        let targetPrimaryScreen = allScreens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? allScreens.first

        guard let primaryScreen = targetPrimaryScreen else {
            ReminderLogger.shared.logError("❌ 未能获取到任何可用显示器，无法弹出蒙版")
            return
        }

        // 创建主控屏蒙版窗口
        let pWin = ReminderPrimaryOverlayWindow(
            screen: primaryScreen,
            state: state,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        self.primaryWindow = pWin

        // 为其余屏幕创建副屏蒙版窗口
        var sWins: [ReminderSecondaryOverlayWindow] = []
        for screen in allScreens where screen != primaryScreen {
            let sWin = ReminderSecondaryOverlayWindow(screen: screen)
            sWins.append(sWin)
        }
        self.secondaryWindows = sWins

        // 安装事件监听（吞掉全局按键与滚轮事件）
        removeEventMonitors()
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in nil }
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { _ in nil }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { _ in nil }

        // 先置顶显示所有副屏遮罩
        for sWin in secondaryWindows {
            sWin.orderFrontRegardless()
        }

        // 置顶显示主控屏遮罩并激活 Key 焦点
        pWin.orderFrontRegardless()
        pWin.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        ReminderLogger.shared.logInfo("🖥️ 蒙版弹出完成，总屏幕数: \(allScreens.count)，主控屏: \(primaryScreen.frame)")
    }

    func dismiss() {
        guard isVisible else { return }

        dismissWindows()
        removeEventMonitors()

        Task { @MainActor in
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey && $0.level == .normal }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        onDismiss()
        onContinue?()
    }

    func close() {
        dismiss()
    }

    private func dismissWindows() {
        primaryWindow?.orderOut(nil)
        primaryWindow = nil

        for win in secondaryWindows {
            win.orderOut(nil)
        }
        secondaryWindows.removeAll()
    }

    private func relayoutWindows() {
        guard isVisible else { return }
        ReminderLogger.shared.logInfo("🖥️ 检测到屏幕参数发生变化，重新布局蒙版")
        dismissWindows()
        show()
    }

    private func setupWakeObserver() {
        wakeObserver = NotificationCenter.default.addObserver(
            forName: .systemDidWake, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isVisible else { return }
                self.dismiss()
            }
        }
    }

    private func setupScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.relayoutWindows()
            }
        }
    }

    private func removeEventMonitors() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
        if let m = flagsChangedMonitor { NSEvent.removeMonitor(m); flagsChangedMonitor = nil }
        if let m = scrollWheelMonitor { NSEvent.removeMonitor(m); scrollWheelMonitor = nil }
    }
}

/// 兼容别名
typealias ReminderOverlayController = ReminderOverlayWindow

// MARK: - SwiftUI 视图（主控屏）

struct ReminderPrimaryOverlayView: View {
    @ObservedObject var state: ReminderOverlayState
    let onDismiss: () -> Void

    @State private var isHoveringButton = false

    var body: some View {
        ZStack {
            VStack(spacing: 40) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)

                Text(L10n.tr("reminder.timeForBreak"))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)

                Text(state.message)
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 80)
                    .fixedSize(horizontal: false, vertical: true)

                // 倒计时
                if let time = state.remainingTime {
                    Text(time)
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }

                Button(action: onDismiss) {
                    Text(L10n.tr("reminder.restLater"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 60)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isHoveringButton ? Color.blue : Color.blue.opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isHoveringButton = hovering
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .onDisappear {
                    if isHoveringButton {
                        NSCursor.pop()
                        isHoveringButton = false
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SwiftUI 视图（副屏）

struct ReminderSecondaryOverlayView: View {
    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.85))

                Text(L10n.tr("reminder.resting"))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// 保持历史兼容别名
typealias ReminderOverlayView = ReminderPrimaryOverlayView
