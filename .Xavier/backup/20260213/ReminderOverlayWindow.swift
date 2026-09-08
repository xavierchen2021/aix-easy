import AppKit
import SwiftUI

/// 提醒休息蒙版窗口（简化版：只有一种状态）
class ReminderOverlayWindow: NSWindow {
    var onContinue: (() -> Void)?
    var message: String
    var remainingTime: String?

    // 事件监听器
    private var keyDownMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var scrollWheelMonitor: Any?
    private var wakeObserver: NSObjectProtocol?
    private let onDismiss: () -> Void

    init(message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        setupWindow()
        setupContentView()
        setupWakeObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Window Setup

    private func setupWindow() {
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

        let frame = NSScreen.main?.frame ?? .zero
        setFrame(frame, display: true)

        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }

    override var acceptsFirstResponder: Bool { false }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func setupContentView() {
        let rootView = ReminderOverlayView(
            message: Binding(get: { self.message }, set: { self.message = $0 }),
            remainingTime: Binding(get: { self.remainingTime }, set: { self.remainingTime = $0 })
        ) {
            self.dismiss()
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        hostingView.frame = contentView!.bounds
        contentView?.addSubview(hostingView)
    }

    private func setupWakeObserver() {
        wakeObserver = NotificationCenter.default.addObserver(
            forName: .systemDidWake, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isVisible else { return }
            Task { @MainActor in self.dismiss() }
        }
    }

    // MARK: - Show / Dismiss

    func show() {
        if isVisible {
            contentView?.subviews.forEach { $0.removeFromSuperview() }
            setupContentView()
            return
        }

        removeEventMonitors()
        contentView?.subviews.forEach { $0.removeFromSuperview() }
        setupContentView()

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in nil }
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { _ in nil }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { _ in nil }

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        orderOut(nil)
        removeEventMonitors()

        Task { @MainActor in
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey && $0 != self && $0.level == .normal }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        onDismiss()
        onContinue?()
    }

    override func close() {
        removeEventMonitors()
        super.close()
    }

    private func removeEventMonitors() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
        if let m = flagsChangedMonitor { NSEvent.removeMonitor(m); flagsChangedMonitor = nil }
        if let m = scrollWheelMonitor { NSEvent.removeMonitor(m); scrollWheelMonitor = nil }
        if let o = wakeObserver { NotificationCenter.default.removeObserver(o); wakeObserver = nil }
    }
}

// MARK: - SwiftUI View

struct ReminderOverlayView: View {
    @Binding var message: String
    @Binding var remainingTime: String?
    let onDismiss: () -> Void

    @State private var isHoveringButton = false

    var body: some View {
        ZStack {
            VStack(spacing: 40) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)

                Text("该休息一下了")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)

                Text(message)
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 80)
                    .fixedSize(horizontal: false, vertical: true)

                // 倒计时
                if let time = remainingTime {
                    Text(time)
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }

                Button(action: onDismiss) {
                    Text("稍后休息")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 60)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.8))
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
