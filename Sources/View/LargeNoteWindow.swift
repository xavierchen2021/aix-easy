import Cocoa
import SwiftUI
import MarkdownUI

class LargeNoteWindow: NSPanel {
    static var shared: LargeNoteWindow?
    
    init(note: Note) {
        let contentView = LargeNoteView(note: note)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let windowWidth: CGFloat = 600
        let windowHeight: CGFloat = 500
        
        // 定位在笔记列表窗口右侧
        let windowRect: NSRect
        if let noteWindow = NSApp.windows.first(where: { $0 is NoteWindow && $0.isVisible }) {
            let noteFrame = noteWindow.frame
            let x = noteFrame.maxX + 8 // 笔记列表右侧，间隔 8pt
            let y = noteFrame.midY - windowHeight / 2 // 垂直居中对齐
            // 确保不超出屏幕右边缘
            let finalX = min(x, screenFrame.maxX - windowWidth)
            let finalY = max(min(y, screenFrame.maxY - windowHeight), screenFrame.minY)
            windowRect = NSRect(x: finalX, y: finalY, width: windowWidth, height: windowHeight)
        } else {
            windowRect = NSRect(
                x: screenFrame.midX - windowWidth / 2,
                y: screenFrame.midY - windowHeight / 2,
                width: windowWidth,
                height: windowHeight
            )
        }
        
        super.init(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        self.contentView = hostingView
        
        // 确保可以接收输入
        self.becomesKeyOnlyIfNeeded = false
    }
    
    static func show(note: Note) {
        if shared == nil {
            shared = LargeNoteWindow(note: note)
        } else {
            let hostingView = NSHostingView(rootView: LargeNoteView(note: note))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            shared?.contentView = hostingView
            // 重新定位到笔记列表右侧
            shared?.repositionNextToNoteWindow()
        }
        shared?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func repositionNextToNoteWindow() {
        let screenFrame = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if let noteWindow = NSApp.windows.first(where: { $0 is NoteWindow && $0.isVisible }) {
            let noteFrame = noteWindow.frame
            let x = min(noteFrame.maxX + 8, screenFrame.maxX - self.frame.width)
            let y = max(min(noteFrame.midY - self.frame.height / 2, screenFrame.maxY - self.frame.height), screenFrame.minY)
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        // Ctrl+S 触发保存
        if event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers == "s" {
            NotificationCenter.default.post(name: Notification.Name("LargeNoteWindowSave"), object: nil)
            return
        }
        super.keyDown(with: event)
    }
}

struct LargeNoteView: View {
    let note: Note
    @State private var editedContent: String
    @State private var debouncedTask: Task<Void, Never>? = nil
    @State private var hasUnsavedChanges: Bool = false
    @State private var isAppearing: Bool = false
    @State private var isRendering: Bool = false
    @State private var savedScrollRatio: CGFloat = 0   // 切换时保存滚动进度(0~1)
    
    init(note: Note) {
        self.note = note
        _editedContent = State(initialValue: note.content)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                Text("编辑笔记")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                // 渲染切换按钮
                Button(action: {
                    if !isRendering {
                        // 切换到渲染前，记录当前滚动比例
                        savedScrollRatio = Self.currentScrollRatio()
                    }
                    withAnimation(.easeInOut(duration: 0.15)) { isRendering.toggle() }
                }) {
                    Image(systemName: isRendering ? "doc.plaintext" : "eye")
                        .font(.system(size: 16))
                        .foregroundColor(isRendering ? .white.opacity(0.9) : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(isRendering ? "切换到编辑模式" : "渲染 Markdown")
                .padding(.trailing, 4)
                
                Button(action: {
                    saveAndClose()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            // 普通笔记：可编辑
            normalEditorView
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: note.colorHex))
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.4), location: 0),
                                .init(color: .white.opacity(0.05), location: 0.15),
                                .init(color: .clear, location: 0.5),
                                .init(color: .black.opacity(0.1), location: 0.8),
                                .init(color: .black.opacity(0.25), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        .scaleEffect(isAppearing ? 1.0 : 0.9)
        .opacity(isAppearing ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isAppearing = true
            }
        }
        .onDisappear {
            forceSaveIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LargeNoteWindowSave"))) { _ in
            forceSaveIfNeeded()
        }
    }
    

    
    // MARK: - 普通编辑视图
    private var normalEditorView: some View {
        Group {
            if isRendering {
                // Markdown 渲染模式（只读）
                ScrollView(showsIndicators: false) {
                    Markdown(editedContent)
                        .markdownTheme(MarkdownDarkTheme.large)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .frame(maxHeight: .infinity)
                .onAppear {
                    // 短暂延迟后按保存的比例恢复滚动位置
                    let ratio = savedScrollRatio
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        Self.restoreScrollRatio(ratio)
                    }
                }
            } else {
                // 源码编辑模式
                TextEditor(text: $editedContent)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .padding()
                    .cornerRadius(8)
                    .padding([.leading, .trailing, .bottom])
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = LargeNoteWindow.shared,
                               let scrollView = Self.findScrollView(in: window.contentView) {
                                scrollView.hasVerticalScroller = false
                                scrollView.hasHorizontalScroller = false
                            }
                        }
                    }
            }
        }
        .onChange(of: editedContent) { _, newValue in
            hasUnsavedChanges = true
            debouncedTask?.cancel()
            debouncedTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run {
                        var updatedNote = note
                        updatedNote.content = newValue
                        NoteManager.shared.updateNote(updatedNote)
                        hasUnsavedChanges = false
                    }
                } catch {}
            }
        }
    }
    
    private func saveAndClose() {
        // 关闭前强制保存
        forceSaveIfNeeded()
        LargeNoteWindow.shared?.orderOut(nil)
    }
    
    private func forceSaveIfNeeded() {
        debouncedTask?.cancel()
        debouncedTask = nil
        
        if hasUnsavedChanges && editedContent != note.content {
            var updatedNote = note
            updatedNote.content = editedContent
            NoteManager.shared.updateNote(updatedNote)
            hasUnsavedChanges = false
        }
    }
    
    private static func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view = view else { return nil }
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
    
    /// 读取当前可见 NSScrollView 的滚动比例 (0~1)
    private static func currentScrollRatio() -> CGFloat {
        guard let window = LargeNoteWindow.shared,
              let sv = findScrollView(in: window.contentView),
              let docView = sv.documentView else { return 0 }
        let docH = docView.frame.height
        let visH = sv.contentView.bounds.height
        let maxY = max(docH - visH, 1)
        return sv.contentView.bounds.origin.y / maxY
    }
    
    /// 按比例恢复 NSScrollView 滚动位置
    private static func restoreScrollRatio(_ ratio: CGFloat) {
        guard let window = LargeNoteWindow.shared,
              let sv = findScrollView(in: window.contentView),
              let docView = sv.documentView else { return }
        let docH = docView.frame.height
        let visH = sv.contentView.bounds.height
        let maxY = max(docH - visH, 0)
        let targetY = ratio * maxY
        sv.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        sv.reflectScrolledClipView(sv.contentView)
    }
}
