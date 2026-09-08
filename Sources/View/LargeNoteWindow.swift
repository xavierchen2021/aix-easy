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
    @State private var isStreaming: Bool = false
    @State private var aiInputText: String = ""
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
                Text(note.isAI ? "AI 问答" : "编辑笔记")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                // 流式输出中显示加载指示
                if isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                
                // 普通笔记：渲染切换按钮
                if !note.isAI {
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
                }
                
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
            
            if note.isAI {
                // AI 笔记：只读对话内容 + 底部输入框
                aiConversationView
            } else {
                // 普通笔记：可编辑
                normalEditorView
            }
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
            if note.isAI && !isStreaming {
                sendAIMessage()
            } else {
                forceSaveIfNeeded()
            }
        }
        .onReceive(NoteManager.shared.$notes) { notes in
            // 监听笔记更新（AI 流式输出时内容会不断变化）
            if note.isAI, let updated = notes.first(where: { $0.id == note.id }) {
                editedContent = updated.content
            }
        }
    }
    
    // MARK: - AI 对话视图
    private var aiConversationView: some View {
        VStack(spacing: 0) {
            // 只读对话内容
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    if editedContent.isEmpty {
                        Text(L10n.tr("largeWindow.typeQuestion"))
                            .foregroundColor(.white.opacity(0.4))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        let pairs = parseQAPairsFromContent(editedContent)
                        if pairs.isEmpty {
                            // 无问答对，回退纯文本
                            Text(editedContent)
                                .foregroundColor(.white)
                                .font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .textSelection(.enabled)
                                .id("largeNoteBottom")
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                                    let isLast = index == pairs.count - 1
                                    let isLastStreaming = isStreaming && isLast
                                    // 每轮对话容器
                                    VStack(alignment: .leading, spacing: 6) {
                                        // 问题行
                                        Text("我：\(pair.question)")
                                            .foregroundColor(.white.opacity(0.7))
                                            .font(.system(size: 13, weight: .medium))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        // AI 回答
                                        if let answer = pair.answer, !answer.isEmpty {
                                            if isLastStreaming {
                                                Text(answer)
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 14))
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .textSelection(.enabled)
                                            } else {
                                                Markdown(answer)
                                                    .markdownTheme(MarkdownDarkTheme.large)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .textSelection(.enabled)
                                            }
                                        } else if isLastStreaming {
                                            ProgressView().scaleEffect(0.5).tint(.white)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.white.opacity(0.05))
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        // 复制本轮对话按钮（已完成的轮次才显示）
                                        if !isLastStreaming, pair.answer != nil {
                                            Button(action: {
                                                let roundText = buildRoundText(pair)
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(roundText, forType: .string)
                                            }) {
                                                Image(systemName: "doc.on.doc")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.white.opacity(0.45))
                                                    .padding(6)
                                            }
                                            .buttonStyle(.plain)
                                            .help("复制本轮对话")
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.bottom, isLast ? 0 : 8)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .id("largeNoteBottom")
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .onChange(of: editedContent) {
                    scrollProxy.scrollTo("largeNoteBottom", anchor: .bottom)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollProxy.scrollTo("largeNoteBottom", anchor: .bottom)
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // 底部输入框
            HStack(spacing: 8) {
                TextField("", text: $aiInputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .tint(.white)
                    .lineLimit(1...4)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(alignment: .leading) {
                        if aiInputText.isEmpty {
                            Text(L10n.tr("largeWindow.placeholder"))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.leading, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .onSubmit {
                        sendAIMessage()
                    }
                
                Button(action: sendAIMessage) {
                    Image(systemName: isStreaming ? "stop.circle.fill" : "paperplane.fill")
                        .foregroundColor(isStreaming || !aiInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.8) : .white.opacity(0.3))
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(!isStreaming && aiInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
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
    
    /// AI 大窗口发送消息
    private func sendAIMessage() {
        // 如果正在流式输出，点击则取消
        if isStreaming {
            if let sessionId = note.aiSessionId {
                AIService.shared.cancelStream(sessionId: sessionId)
            }
            isStreaming = false
            return
        }
        
        let question = aiInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let preferredSessionId = note.aiSessionId ?? ""
        
        isStreaming = true
        
        // 构建内容
        var newContent = editedContent
        if !newContent.isEmpty {
            newContent += "\n\n"
        }
        newContent += "我：\(question)\n\n"
        
        // 清空输入框
        aiInputText = ""
        
        // 更新笔记内容
        editedContent = newContent
        var updatedNote = note
        updatedNote.content = newContent
        NoteManager.shared.updateNote(updatedNote)
        
        AIService.shared.sendQuestion(
            noteContent: newContent,
            sessionId: preferredSessionId,
            onSessionReady: { resolvedSessionId in
                Task { @MainActor in
                    if let idx = NoteManager.shared.notes.firstIndex(where: { $0.id == note.id }),
                       NoteManager.shared.notes[idx].aiSessionId != resolvedSessionId {
                        NoteManager.shared.notes[idx].aiSessionId = resolvedSessionId
                        try? AppDatabase.shared.noteStore.insertNote(NoteManager.shared.notes[idx])
                    }
                }
            },
            onChunk: { chunk in
                Task { @MainActor in
                    // 通过 NoteManager 更新，onReceive 会自动同步 editedContent
                    if let idx = NoteManager.shared.notes.firstIndex(where: { $0.id == note.id }) {
                        NoteManager.shared.notes[idx].content += chunk
                        try? AppDatabase.shared.noteStore.insertNote(NoteManager.shared.notes[idx])
                    }
                }
            },
            onComplete: {
                Task { @MainActor in
                    isStreaming = false
                }
            },
            onError: { error in
                Task { @MainActor in
                    if let idx = NoteManager.shared.notes.firstIndex(where: { $0.id == note.id }) {
                        NoteManager.shared.notes[idx].content += "\n[错误: \(error)]"
                        try? AppDatabase.shared.noteStore.insertNote(NoteManager.shared.notes[idx])
                    }
                    isStreaming = false
                }
            }
        )
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
    
    // MARK: - QA 解析辅助
    
    /// 按"我：" 或 "问：" 前缀解析出 [(question, answer?)] 数组
    private func parseQAPairsFromContent(_ content: String) -> [(question: String, answer: String?)] {
        var pairs: [(question: String, answer: String?)] = []
        let separator = content.contains("我：") ? "我：" : "问："
        let parts = content.components(separatedBy: separator)
        for (index, part) in parts.enumerated() {
            if index == 0 { continue }
            if part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            // 兼容旧格式"答："分隔
            if let ar = part.range(of: "\n答：") {
                let q = String(part[part.startIndex..<ar.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let a = String(part[ar.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                pairs.append((q, a.isEmpty ? nil : a))
            } else if let dr = part.range(of: "\n\n") {
                let q = String(part[part.startIndex..<dr.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let a = String(part[dr.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                pairs.append((q, a.isEmpty ? nil : a))
            } else {
                let q = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty { pairs.append((q, nil)) }
            }
        }
        return pairs
    }
    
    /// 构建一轮对话的文本，用于复制
    private func buildRoundText(_ pair: (question: String, answer: String?)) -> String {
        var text = "我：\(pair.question)"
        if let answer = pair.answer, !answer.isEmpty {
            text += "\n\n\(answer)"
        }
        return text
    }
}
