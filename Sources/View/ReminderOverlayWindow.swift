import AppKit
import SwiftUI

// MARK: - 蒙版状态数据模型

@MainActor
final class ReminderOverlayState: ObservableObject {
    @Published var message: String
    @Published var remainingTime: String?
    @Published var isRestCompleted: Bool

    init(message: String, remainingTime: String?, isRestCompleted: Bool = false) {
        self.message = message
        self.remainingTime = remainingTime
        self.isRestCompleted = isRestCompleted
    }
}

// MARK: - 主控屏蒙版窗口

/// 主控屏幕蒙版窗口（包含倒计时与「稍后休息」/「开始工作」控制按钮）
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
        // 倒计时结束前屏蔽所有按键；倒计时结束后允许回车键（Return/Enter: 36, 76）或空格键（Space: 49）触发开始工作
        if state.isRestCompleted {
            let code = event.keyCode
            if code == 36 || code == 76 || code == 49 {
                onDismissAction()
                return
            }
        }
    }
}

// MARK: - 副屏蒙版窗口

/// 副屏蒙版窗口（显示深色遮罩背景与状态提示，拦截鼠标键盘）
final class ReminderSecondaryOverlayWindow: NSWindow {
    private let state: ReminderOverlayState

    init(screen: NSScreen, state: ReminderOverlayState) {
        self.state = state

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
        let rootView = ReminderSecondaryOverlayView(state: state)
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
    var isRestCompleted: Bool {
        get { state.isRestCompleted }
        set { state.isRestCompleted = newValue }
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
        state.isRestCompleted = false

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
            let sWin = ReminderSecondaryOverlayWindow(screen: screen, state: state)
            sWins.append(sWin)
        }
        self.secondaryWindows = sWins

        // 安装事件监听（未完成时屏蔽所有键盘事件；完成后允许按 Return/Enter 或 Space 快捷开始工作）
        removeEventMonitors()
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return nil }
            if self.state.isRestCompleted {
                let code = event.keyCode
                if code == 36 || code == 76 || code == 49 {
                    self.dismiss()
                    return nil
                }
            }
            return nil
        }
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
                Image(systemName: state.isRestCompleted ? "checkmark.circle.fill" : "bed.double.fill")
                    .font(.system(size: 80))
                    .foregroundColor(state.isRestCompleted ? .green : .white)

                Text(state.isRestCompleted ? L10n.tr("reminder.restCompleted") : L10n.tr("reminder.timeForBreak"))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)

                Text(state.message)
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 80)
                    .fixedSize(horizontal: false, vertical: true)

                // 倒计时（休息进行中显示倒计时；结束后保持 00:00）
                if let time = state.remainingTime {
                    Text(time)
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .foregroundColor(state.isRestCompleted ? .white.opacity(0.6) : .white.opacity(0.85))
                }

                Button(action: onDismiss) {
                    HStack(spacing: 10) {
                        if state.isRestCompleted {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18))
                        }
                        Text(state.isRestCompleted ? L10n.tr("reminder.startWork") : L10n.tr("reminder.restLater"))
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                state.isRestCompleted
                                    ? (isHoveringButton ? Color.blue : Color.blue.opacity(0.85))
                                    : (isHoveringButton ? Color.blue.opacity(0.8) : Color.blue.opacity(0.6))
                            )
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
    @ObservedObject var state: ReminderOverlayState

    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Image(systemName: state.isRestCompleted ? "checkmark.circle.fill" : "bed.double.fill")
                    .font(.system(size: 80))
                    .foregroundColor(state.isRestCompleted ? .green : .white.opacity(0.85))

                Text(state.isRestCompleted ? L10n.tr("reminder.restCompleted") : L10n.tr("reminder.resting"))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// 保持历史兼容别名
typealias ReminderOverlayView = ReminderPrimaryOverlayView
