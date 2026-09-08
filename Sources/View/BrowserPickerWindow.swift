import SwiftUI
import AppKit

// MARK: - BrowserPickerWindow

@MainActor
class BrowserPickerWindow {
    static let shared = BrowserPickerWindow()
    private var window: NSPanel?
    private var pendingURL: URL?
    private var autoCloseWorkItem: DispatchWorkItem?
    
    func show(for url: URL) {
        pendingURL = url
        
        if let existingWindow = window, existingWindow.isVisible {
            // 窗口已存在，更新 URL
            existingWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let browsers = BrowserDetector.shared.detectBrowsers()
        
        let contentView = BrowserPickerView(
            url: url,
            browsers: browsers,
            onSelect: { [weak self] browser in
                guard let self = self, let url = self.pendingURL else { return }
                BrowserDetector.shared.openURL(url, with: browser)
                self.scheduleAutoClose()
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        
        // 计算面板大小
        let panelWidth: CGFloat = 320
        let rowHeight: CGFloat = 52
        let headerHeight: CGFloat = 80
        let footerHeight: CGFloat = 16
        let maxRows: CGFloat = 8
        let contentHeight = min(CGFloat(browsers.count) * rowHeight, maxRows * rowHeight)
        let panelHeight = headerHeight + contentHeight + footerHeight
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.center()
        
        // 设置窗口关闭行为
        panel.isReleasedWhenClosed = false
        
        self.window = panel
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        autoCloseWorkItem?.cancel()
        autoCloseWorkItem = nil
        window?.orderOut(nil)
        window = nil
        pendingURL = nil
    }
    
    /// 根据配置安排自动关闭
    private func scheduleAutoClose() {
        autoCloseWorkItem?.cancel()
        
        let config = FloatingButtonConfigManager.shared.config
        guard config.browserAutoClose else { return }
        
        let delay = config.browserAutoCloseDelay
        if delay <= 0 {
            close()
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.close()
            }
            autoCloseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
}

// MARK: - BrowserPickerView

struct BrowserPickerView: View {
    let url: URL
    let browsers: [BrowserInfo]
    let onSelect: (BrowserInfo) -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部：URL 和关闭按钮
            headerView
            
            Divider()
            
            // 浏览器列表
            if browsers.isEmpty {
                emptyView
            } else {
                browserListView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text(url.host ?? url.absoluteString)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "safari")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(L10n.tr("browser.noBrowsers"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    private var browserListView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(browsers) { browser in
                    BrowserItemView(browser: browser) {
                        onSelect(browser)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - BrowserItemView

struct BrowserItemView: View {
    let browser: BrowserInfo
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 浏览器图标
                Image(nsImage: browser.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                
                // 浏览器名称
                Text(browser.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
