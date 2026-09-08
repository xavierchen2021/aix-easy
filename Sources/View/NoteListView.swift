import SwiftUI
import AppKit
import MarkdownUI

/// 支持文本和闪烁光标垂直居中的 NSTextView
class VerticallyCenteredTextView: NSTextView {
    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer else {
            return origin
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        var contentHeight = usedRect.height
        if string.isEmpty || contentHeight < 1 {
            if let font = self.font {
                contentHeight = layoutManager.defaultLineHeight(for: font)
            } else {
                contentHeight = 16
            }
        }
        let dy = (bounds.height - contentHeight) / 2
        return NSPoint(x: origin.x, y: max(0, floor(dy)))
    }
}

// 自定义 TextEditor，支持 Enter 完成编辑，Shift+Enter 换行，支持垂直居中
struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onSubmit: () -> Void
    var shouldBecomeFirstResponder: Bool = false
    var protectedPrefix: String? = nil
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(containerSize: NSSize(width: 220, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        
        let textView = VerticallyCenteredTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.alphaValue = 0
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        
        context.coordinator.textView = textView
        
        // 初始化时立即计算一次高度
        DispatchQueue.main.async {
            context.coordinator.updateHeight()
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        
        // 只有当内容真正发生变化时才更新，且需要保留光标位置
        if textView.string != text {
            let wasEmpty = textView.string.isEmpty
            // 保存当前的光标位置和选择范围
            let selectedRanges = textView.selectedRanges
            
            textView.string = text
            
            if wasEmpty && !text.isEmpty {
                // 首次填充文本：光标定位到末尾
                textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
            } else if shouldBecomeFirstResponder && textView.window?.firstResponder != textView {
                // 即将获得焦点时（如再次对话），光标定位到末尾
                textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
            } else if !selectedRanges.isEmpty {
                // 后续更新：恢复光标位置
                textView.selectedRanges = selectedRanges
            }
            
            // 只有在内容变化时才更新高度
            DispatchQueue.main.async {
                context.coordinator.updateHeight()
            }
        }
        
        // 如果需要成为第一响应者，且当前还不是第一响应者
        if shouldBecomeFirstResponder && textView.window?.firstResponder != textView {
            DispatchQueue.main.async {
                if let window = textView.window {
                    // 激活应用程序，确保窗口能接收键盘输入
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    
                    if !window.isKeyWindow {
                        window.makeKeyAndOrderFront(nil)
                    }
                    window.makeFirstResponder(textView)
                    // 确保光标定位到末尾
                    textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        weak var textView: NSTextView?
        
        init(_ parent: CustomTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight()
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let protectedPrefix = parent.protectedPrefix else { return true }
            
            let nsString = textView.string as NSString
            // 找到最后一个被保护前缀的位置
            let searchRange = NSRange(location: 0, length: nsString.length)
            let lastRange = nsString.range(of: protectedPrefix, options: .backwards, range: searchRange)
            
            guard lastRange.location != NSNotFound else { return true }
            
            let protectedEnd = lastRange.location + lastRange.length
            let editEnd = affectedCharRange.location + affectedCharRange.length
            
            // 如果编辑范围与保护前缀区域重叠，拒绝修改
            if editEnd > lastRange.location && affectedCharRange.location < protectedEnd {
                return false
            }
            
            return true
        }
        
        @MainActor
        func updateHeight() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            
            // 强制布局
            layoutManager.ensureLayout(for: textContainer)
            
            // 获取实际使用的矩形
            let usedRect = layoutManager.usedRect(for: textContainer)
            
            // 计算高度
            var contentHeight = usedRect.height
            
            // 如果内容为空，使用字体的行高
            if textView.string.isEmpty || contentHeight < 1 {
                if let font = textView.font {
                    contentHeight = layoutManager.defaultLineHeight(for: font)
                } else {
                    contentHeight = 17 // 后备值
                }
            }
            
            // 限制最大668（约30行）
            let newHeight = min(contentHeight, 668)
            
            if abs(parent.height - newHeight) > 1 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    parent.height = newHeight
                }
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // 如果正在进行输入法转换，不处理回车
                if textView.hasMarkedText() {
                    return false
                }
                
                // 检查是否按下了 Shift 键
                if NSEvent.modifierFlags.contains(.shift) {
                    // Shift+Enter：插入换行符
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    // 单独的 Enter：完成编辑
                    parent.onSubmit()
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - AI 笔记项视图（聊天式交互）
struct AINoteItemView: View {
    var note: Note
    var onDelete: () -> Void
    
    @State private var inputText: String = ""
    @State private var inputHeight: CGFloat = 20
    @State private var isHovered = false
    @State private var isStreaming = false
    @State private var showCopiedToKnowledgeToast = false
    @FocusState private var isInputFocused: Bool
    @StateObject private var configManager = FloatingButtonConfigManager.shared
    @StateObject private var noteManager = NoteManager.shared
    
    /// 从 NoteManager 获取实时笔记内容
    private var currentNote: Note {
        noteManager.notes.first(where: { $0.id == note.id }) ?? note
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputBarView
            conversationContentView
        }
        .highPriorityGesture(TapGesture(count: 2).onEnded {
            LargeNoteWindow.show(note: currentNote)
        })
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(noteBackground)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }

        }
        .onAppear {
            // 新建 AI 笔记自动聚焦输入框
            if note.content.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // 应用失焦时，如果内容为空则删除
            if currentNote.content.isEmpty && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NoteManager.shared.permanentDeleteEmpty(id: note.id)
            }
        }
        .onTapGesture {
            // 阻止点击事件向上传播
        }
        .overlay(alignment: .center) {
            if showCopiedToKnowledgeToast {
                Text(L10n.tr("notes.copiedToKnowledge"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .transition(.opacity)
            }
        }
    }
    
    // MARK: - 输入栏子视图
    private var inputBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.white)
                .font(.system(size: 16))
            
            CustomTextEditor(text: $inputText, height: $inputHeight, onSubmit: sendMessage, shouldBecomeFirstResponder: isInputFocused)
                .focused($isInputFocused)
                .frame(width: 160, height: min(inputHeight, 80), alignment: .leading)
            
            // 右侧按钮组 - 始终显示
            actionButtonsView
        }
    }
    
    // MARK: - 操作按钮子视图
    private var actionButtonsView: some View {
        HStack(spacing: 6) {
            if isStreaming {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
                    .tint(.white)
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.3) : .white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            if !currentNote.content.isEmpty {
                Button(action: {
                    copyNoteToClipboard(currentNote.content)
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 对话内容子视图
    @ViewBuilder
    private var conversationContentView: some View {
        if !currentNote.content.isEmpty {
            let displayText = currentNote.content.count > 300
                ? String(currentNote.content.suffix(300))
                : currentNote.content
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Text(displayText)
                        .foregroundColor(.white)
                        .font(.system(size: 13))
                        .frame(width: 260, alignment: .leading)
                        .id("aiContentBottom")
                }
                .frame(minWidth: 260, maxWidth: 260, maxHeight: 300, alignment: .leading)
                .padding(.top, 4)
                .onChange(of: currentNote.content) {
                    scrollProxy.scrollTo("aiContentBottom", anchor: .bottom)
                }
                .onAppear {
                    scrollProxy.scrollTo("aiContentBottom", anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isHovered && !currentNote.content.isEmpty {
                    Text(L10n.tr("notes.doubleClickToTry"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.8))
                        .cornerRadius(4)
                        .padding(6)
                        .transition(.opacity)
                }
            }
            .contextMenu {
                Button(L10n.tr("notes.viewInLargeWindow")) {
                    LargeNoteWindow.show(note: currentNote)
                }
                Button(L10n.tr("notes.copyContent")) {
                    copyNoteToClipboard(currentNote.content)
                }
                Menu("复制到知识库") {
                    ForEach(NoteManager.shared.getSortedGroups(isKnowledgeGroup: true)) { group in
                        Button(group.name) {
                            NoteManager.shared.copyToKnowledge(content: currentNote.content, toGroupId: group.id)
                            showCopiedToKnowledgeToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopiedToKnowledgeToast = false
                            }
                        }
                    }
                }
                Divider()
                if currentNote.pinnedAt != nil {
                    Button(L10n.tr("notes.unpin")) {
                        NoteManager.shared.unpinNote(id: currentNote.id)
                    }
                } else {
                    Button(L10n.tr("notes.moveToTop")) {
                        NoteManager.shared.moveToTop(id: currentNote.id)
                    }
                }
                Divider()
                Button(L10n.tr("notes.deleteNote"), role: .destructive) {
                    onDelete()
                }
            }
        }
    }
    
    // MARK: - 背景子视图
    private var noteBackground: some View {
        Group {
            if configManager.config.noteTheme == .gradient {
                let baseColor = Color(hex: note.colorHex)
                let opacity = configManager.config.noteOpacity
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(baseColor.opacity(opacity))
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white.opacity(0.6), location: 0),
                                    .init(color: .white.opacity(0.1), location: 0.15),
                                    .init(color: .clear, location: 0.5),
                                    .init(color: .black.opacity(0.1), location: 0.8),
                                    .init(color: .black.opacity(0.3), location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: note.colorHex).opacity(configManager.config.noteOpacity))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.5), lineWidth: 2)
        )
    }
    
    /// 发送消息
    private func sendMessage() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let preferredSessionId = currentNote.aiSessionId ?? ""
        
        isStreaming = true
        let noteId = note.id
        
        // 构建内容：在现有内容后追加问答（使用 currentNote 获取实时内容）
        var newContent = currentNote.content
        if !newContent.isEmpty {
            newContent += "\n\n"
        }
        newContent += "我：\(question)\n\n"
        
        // 清空输入框
        inputText = ""
        
        // 更新笔记内容
        var updatedNote = currentNote
        updatedNote.content = newContent
        NoteManager.shared.updateNote(updatedNote)
        
        AIService.shared.sendQuestion(
            noteContent: newContent,
            sessionId: preferredSessionId,
            onSessionReady: { resolvedSessionId in
                Task { @MainActor in
                    if var latestNote = NoteManager.shared.notes.first(where: { $0.id == noteId }), latestNote.aiSessionId != resolvedSessionId {
                        latestNote.aiSessionId = resolvedSessionId
                        NoteManager.shared.updateNote(latestNote)
                    }
                }
            },
            onChunk: { chunk in
                Task { @MainActor in
                    newContent += chunk
                    if var latestNote = NoteManager.shared.notes.first(where: { $0.id == noteId }) {
                        latestNote.content = newContent
                        NoteManager.shared.updateNote(latestNote)
                    }
                }
            },
            onComplete: {
                Task { @MainActor in
                    isStreaming = false
                    NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
                }
            },
            onError: { error in
                Task { @MainActor in
                    newContent += "\n[错误: \(error)]"
                    if var latestNote = NoteManager.shared.notes.first(where: { $0.id == noteId }) {
                        latestNote.content = newContent
                        NoteManager.shared.updateNote(latestNote)
                    }
                    isStreaming = false
                }
            }
        )
    }
    
    private func copyNoteToClipboard(_ text: String) {
        if let data = text.data(using: .utf8) {
            let clipboardItem = ClipboardItem(id: UUID(), timestamp: Date(), type: .text, data: data)
            ClipboardManager.shared.copyToClipboard(clipboardItem, shouldAddToHistory: true)
        }
    }
}

struct NoteItemView: View {
    var note: Note
    var selectedTag: String? = nil
    var onDelete: () -> Void
    var onToggle: () -> Void
    var onTagClick: ((String) -> Void)? = nil
    
    @State private var content: String
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var showSavedToast = false
    @State private var showTagSheet = false
    @State private var tagInput = ""
    @State private var editingTags: [String] = []
    @State private var contentHeight: CGFloat = 18
    @State private var displayHeight: CGFloat = 0 // 记录显示状态下的实际高度
    @FocusState private var isFocused: Bool
    @StateObject private var configManager = FloatingButtonConfigManager.shared
    
    init(note: Note, selectedTag: String? = nil, onDelete: @escaping () -> Void, onToggle: @escaping () -> Void, onTagClick: ((String) -> Void)? = nil) {
        self.note = note
        self.selectedTag = selectedTag
        self.onDelete = onDelete
        self.onToggle = onToggle
        self.onTagClick = onTagClick
        _content = State(initialValue: note.content)
        _tagInput = State(initialValue: "")
        _editingTags = State(initialValue: note.tags)
        // 初始化时计算内容高度
        let lineCount = max(1, note.content.components(separatedBy: .newlines).count)
        let estimatedHeight = note.content.isEmpty ? 18 : min(max(CGFloat(lineCount) * 18 + 8, 18), 668)
        _contentHeight = State(initialValue: estimatedHeight)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 复选框
            if !note.isKnowledge {
                Button(action: onToggle) {
                    Image(systemName: note.isCompleted ? "checkmark.square.fill" : "square")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            
            // 内容与标签展示区
            VStack(alignment: .leading, spacing: 6) {
                if isEditing {
                    CustomTextEditor(text: $content, height: $contentHeight, onSubmit: finishEditing, shouldBecomeFirstResponder: isFocused)
                        .focused($isFocused)
                        .frame(width: 220, height: contentHeight, alignment: .leading)
                        .onChange(of: isFocused) { _, newValue in
                            // 当焦点丢失时自动完成编辑
                            if !newValue && isEditing {
                                finishEditing()
                            }
                        }
                        .onChange(of: contentHeight) { _, _ in
                            // 内容高度变化时通知窗口更新
                            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
                        }
                } else {
                    Text(note.content.isEmpty ? "新笔记..." : note.content)
                        .strikethrough(!note.isKnowledge && note.isCompleted)
                        .foregroundColor(.white)
                        .lineLimit(5)
                        .frame(width: 220, alignment: .leading)
                }

                // 徽章与标签栏（无论是只读还是编辑状态，只要有标签或状态标记均始终显示）
                let noteTags = note.tags
                let hasTags = !noteTags.isEmpty
                if note.isMemory || note.isInProgress || hasTags {
                    HStack(spacing: 6) {
                        if note.isMemory {
                            Label("记忆", systemImage: "brain")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.blue.opacity(0.25)))
                                .foregroundColor(.white)
                        }
                        if note.isInProgress {
                            Label("进行中", systemImage: "bolt.fill")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.85)))
                                .foregroundColor(.white)
                        }
                        ForEach(noteTags, id: \.self) { tagText in
                            Button(action: {
                                onTagClick?(tagText)
                            }) {
                                Label(tagText, systemImage: "tag.fill")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(selectedTag == tagText ? Color.blue.opacity(0.9) : Color.cyan.opacity(0.6)))
                                    .overlay(
                                        Capsule().stroke(Color.white.opacity(selectedTag == tagText ? 0.9 : 0.25), lineWidth: 1)
                                    )
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            displayHeight = geometry.size.height
                        }
                        .onChange(of: note.content) { _, _ in
                            DispatchQueue.main.async {
                                displayHeight = geometry.size.height
                            }
                        }
                }
            )    .contentShape(Rectangle())
                .onLongPressGesture {
                    NoteManager.shared.toggleKnowledge(id: note.id)
                }
                .contextMenu {
                        Button(L10n.tr("notes.editInLargeWindow")) {
                            LargeNoteWindow.show(note: note)
                        }
                        
                        if !note.isKnowledge {
                            Button(note.isCompleted ? "标记为未完成" : "标记为已完成") {
                                onToggle()
                            }
                            
                            Button(note.isInProgress ? "取消进行中" : "标记为进行中") {
                                NoteManager.shared.toggleInProgressMark(id: note.id)
                            }
                        }
                        
                        Button(L10n.tr("notes.copyContent")) {
                            copyNoteToClipboard(note.content)
                        }

                        Button(note.tags.isEmpty ? "添加标签" : "管理标签") {
                            editingTags = note.tags
                            tagInput = ""
                            showTagSheet = true
                        }
                        
                        if !note.tags.isEmpty {
                            Button("清除所有标签") {
                                NoteManager.shared.updateNoteTag(id: note.id, tag: nil)
                            }
                        }
                        
                        Menu("移动到分组") {
                            ForEach(NoteManager.shared.getSortedGroups(isKnowledgeGroup: note.isKnowledge)) { group in
                                Button(group.name) {
                                    NoteManager.shared.moveNote(id: note.id, toGroupId: group.id)
                                }
                                .disabled(note.groupId == group.id)
                            }
                        }
                        
                        if note.isKnowledge {
                            Menu("移动到普通分组") {
                                ForEach(NoteManager.shared.getSortedGroups(isKnowledgeGroup: false)) { group in
                                    Button(group.name) {
                                        NoteManager.shared.moveNote(id: note.id, toGroupId: group.id)
                                    }
                                }
                            }
                        } else {
                            Menu("保存为知识") {
                                ForEach(NoteManager.shared.getSortedGroups(isKnowledgeGroup: true)) { group in
                                    Button(group.name) {
                                        NoteManager.shared.saveAsKnowledge(id: note.id, toGroupId: group.id)
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        if note.pinnedAt != nil {
                            Button(L10n.tr("notes.unpin")) {
                                NoteManager.shared.unpinNote(id: note.id)
                            }
                        } else {
                            Button(L10n.tr("notes.moveToTop")) {
                                NoteManager.shared.moveToTop(id: note.id)
                            }
                        }
                        
                        Divider()
                        
                        Button(L10n.tr("notes.deleteNote"), role: .destructive) {
                            onDelete()
                        }
                    }
            
            // 右侧按钮组 - 支持常驻显示或悬停滑出
            let shouldShowActions = isHovered || configManager.config.alwaysShowNoteActionButtons
            if shouldShowActions {
                HStack(spacing: 8) {
                    // 移动分组按钮
                    Menu {
                        ForEach(NoteManager.shared.getSortedGroups(isKnowledgeGroup: note.isKnowledge)) { group in
                            Button(group.name) {
                                NoteManager.shared.moveNote(id: note.id, toGroupId: group.id)
                            }
                            .disabled(note.groupId == group.id)
                        }
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .frame(height: 20)

                    // 复制按钮
                    Button(action: {
                        copyNoteToClipboard(note.content)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .frame(height: 20)
                    
                    // 删除按钮
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .frame(height: 20)
                }
                .frame(height: 20)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(minHeight: 20)
        .highPriorityGesture(TapGesture(count: 2).onEnded {
            // 双击编辑笔记
            let lineCount = note.content.components(separatedBy: .newlines).count
            if lineCount > 5 {
                LargeNoteWindow.show(note: note)
            } else {
                if note.content.isEmpty {
                    contentHeight = 18
                } else if displayHeight > 0 {
                    contentHeight = displayHeight
                }
                isEditing = true
                NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
            }
        })
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Group {
                if configManager.config.noteTheme == .gradient {
                    let baseColor = Color(hex: note.colorHex)
                    let opacity = (!note.isKnowledge && note.isCompleted) ? configManager.config.noteOpacity * 0.5 : configManager.config.noteOpacity
                    ZStack {
                        // 1. 底色
                        RoundedRectangle(cornerRadius: 20)
                            .fill(baseColor.opacity(opacity))
                        
                        // 2. 凸起光感（上白下黑模拟曲面）
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .white.opacity(0.6), location: 0),
                                        .init(color: .white.opacity(0.1), location: 0.15), // 上部高光
                                        .init(color: .clear, location: 0.5),
                                        .init(color: .black.opacity(0.1), location: 0.8),
                                        .init(color: .black.opacity(0.3), location: 1.0)  // 底部阴影
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(hex: note.colorHex).opacity((!note.isKnowledge && note.isCompleted) ? configManager.config.noteOpacity * 0.5 : configManager.config.noteOpacity))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
            )
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(savedToastOverlay, alignment: .center)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .onAppear {
            // 如果是新创建的空笔记，自动进入编辑模式
            if note.content.isEmpty {
                isEditing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FinishAllNoteEditing"))) { _ in
            // 收到完成编辑通知时，如果当前正在编辑则完成编辑
            if isEditing {
                finishEditing()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // 应用程序失去焦点时完成编辑
            if isEditing {
                finishEditing()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            // 窗口失去焦点时完成编辑
            if isEditing {
                finishEditing()
            }
        }
        .onChange(of: note.content) { _, newContent in
            // 当笔记内容被外部修改（如大窗口编辑）时，同步到本地 @State content
            // 仅在非行内编辑状态下同步，避免覆盖用户正在编辑的内容
            if !isEditing {
                content = newContent
            }
        }
        .onTapGesture {
            // 阻止点击事件向上传播到背景
        }
        .popover(isPresented: $showTagSheet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("管理标签")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(editingTags.count)/3")
                        .font(.caption)
                        .foregroundColor(editingTags.count >= 3 ? .orange : .secondary)
                }
                
                // 已有标签胶囊展示区
                if !editingTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(editingTags, id: \.self) { t in
                                HStack(spacing: 4) {
                                    Text(t)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white)
                                    Button(action: {
                                        editingTags.removeAll { $0 == t }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.blue.opacity(0.85)))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("暂未添加任何标签")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 输入与添加行（达到 3 个时禁用输入与添加）
                HStack(spacing: 6) {
                    TextField(editingTags.count >= 3 ? "最多添加3个标签" : "输入标签名称", text: $tagInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .disabled(editingTags.count >= 3)
                        .onSubmit {
                            addTagFromInput()
                        }
                    
                    Button(action: {
                        addTagFromInput()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(editingTags.count >= 3 || tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                if editingTags.count >= 3 {
                    Text("最多添加 3 个标签")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }

                Divider()

                HStack {
                    Button("取消") {
                        showTagSheet = false
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button("保存") {
                        saveTag()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 230)
        }
    }
    
    private func addTagFromInput() {
        guard editingTags.count < 3 else { return }
        let trimmed = tagInput.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !editingTags.contains(trimmed) {
            editingTags.append(trimmed)
        }
        tagInput = ""
    }
    
    private func saveTag() {
        // 如果输入框中还有未点击添加的内容且未达到3个上限，自动添加进去
        if editingTags.count < 3 {
            let pending = tagInput.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !pending.isEmpty && !editingTags.contains(pending) {
                editingTags.append(pending)
                tagInput = ""
            }
        }
        NoteManager.shared.updateNoteTags(id: note.id, tags: editingTags)
        showTagSheet = false
    }
    
    private func finishEditing() {
        if content.isEmpty {
            // 空笔记直接永久删除，不进回收站
            NoteManager.shared.permanentDeleteEmpty(id: note.id)
        } else {
            isEditing = false
            var updatedNote = note
            updatedNote.content = content
            NoteManager.shared.updateNote(updatedNote)
            // 显示已保存的吐司通知（与剪切板保存为笔记的效果一致）
            withAnimation {
                showSavedToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSavedToast = false
                }
            }
            // 完成编辑后通知窗口更新高度
            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
        }
    }
    
    @ViewBuilder
    private var savedToastOverlay: some View {
        if showSavedToast {
            Text(L10n.tr("notes.saved"))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.green))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                .transition(.scale.combined(with: .opacity))
        }
    }
    
    private func copyNoteToClipboard(_ text: String) {
        // 创建 ClipboardItem 并使用 ClipboardManager 的复制方法，同时添加到历史记录
        if let data = text.data(using: .utf8) {
            let clipboardItem = ClipboardItem(id: UUID(), timestamp: Date(), type: .text, data: data)
            ClipboardManager.shared.copyToClipboard(clipboardItem, shouldAddToHistory: true)
        }
    }
}

struct NoteListView: View {
    @StateObject private var noteManager = NoteManager.shared
    @StateObject private var configManager = FloatingButtonConfigManager.shared
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var viewMode: ViewMode
    @State private var selectedGroupId: UUID
    @State private var selectedTag: String? = nil // 当前被选中的标签过滤条件
    @State private var isShowingGroupManager = false
    @State private var editingNoteId: UUID? = nil // 跟踪当前编辑的笔记ID
    @State private var globalPasswordInput = "" // 全局密码输入
    @State private var globalPasswordError = false // 密码错误标记
    @FocusState private var isSearchFocused: Bool
    
    // 增量加载分页配置
    private let pageSize: Int = 20
    @State private var displayedCount: Int = 20
    
    private let openMode: ViewMode // 记录初始打开模式
    
    /// 是否为笔记相关模式（显示完整工具栏）
    private var isNoteMode: Bool {
        openMode == .all || openMode == .completed || openMode == .knowledge || openMode == .ai
    }
    
    init(initialViewMode: ViewMode = .all) {
        self.openMode = initialViewMode
        _viewMode = State(initialValue: initialViewMode)
        // 根据视图模式设置默认分组
        let config = FloatingButtonConfigManager.shared.config
        if initialViewMode == .knowledge {
            _selectedGroupId = State(initialValue: config.defaultKnowledgeGroupId ?? NoteGroup.defaultKnowledgeId)
        } else {
            _selectedGroupId = State(initialValue: config.defaultNoteGroupId ?? NoteGroup.defaultId)
        }
    }
    
    enum ViewMode {
        case all
        case completed
        case clipboard
        case knowledge
        case ai
        case favorites
        case trash
    }
    
    var filteredNotes: [Note] {
        switch viewMode {
        case .all:
            return noteManager.notes.filter { 
                !$0.isCompleted && 
                !$0.isKnowledge &&
                !$0.isAI &&
                !$0.isDeleted &&
                $0.groupId == selectedGroupId &&
                (selectedTag == nil || $0.tags.contains(selectedTag!)) &&
                (searchText.isEmpty || $0.content.localizedCaseInsensitiveContains(searchText))
            }
        case .completed:
            return noteManager.notes.filter { 
                $0.isCompleted && 
                !$0.isDeleted &&
                $0.groupId == selectedGroupId &&
                (selectedTag == nil || $0.tags.contains(selectedTag!)) &&
                (searchText.isEmpty || $0.content.localizedCaseInsensitiveContains(searchText))
            }
        case .knowledge:
            return noteManager.notes.filter { 
                $0.isKnowledge && 
                !$0.isDeleted &&
                !$0.isAI &&
                $0.groupId == selectedGroupId &&
                (selectedTag == nil || $0.tags.contains(selectedTag!)) &&
                (searchText.isEmpty || $0.content.localizedCaseInsensitiveContains(searchText))
            }
        case .ai:
            return noteManager.notes.filter {
                $0.isAI &&
                !$0.isDeleted &&
                (selectedTag == nil || $0.tags.contains(selectedTag!)) &&
                (searchText.isEmpty || $0.content.localizedCaseInsensitiveContains(searchText))
            }
        case .clipboard:
            return []
        case .favorites:
            return []
        case .trash:
            return []
        }
    }
    
    /// 当前切片展示的笔记条目（分批增量加载）
    var visibleNotes: [Note] {
        let all = filteredNotes
        if displayedCount >= all.count {
            return all
        }
        return Array(all.prefix(displayedCount))
    }
    
    /// 是否还有更多未加载笔记
    var hasMoreNotes: Bool {
        displayedCount < filteredNotes.count
    }
    
    /// 加载下一批笔记
    private func loadMoreNotes() {
        guard hasMoreNotes else { return }
        displayedCount = min(displayedCount + pageSize, filteredNotes.count)
    }
    
    /// 重置增量分页状态
    private func resetPagination() {
        displayedCount = pageSize
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isNoteMode {
                toolbarView
            }
            
            if isNoteMode && (viewMode == .all || viewMode == .completed || viewMode == .knowledge) {
                groupSelectorView
            }
            
            noteListContentView
        }
        .frame(width: isNoteMode ? (isSearching ? 480 : 380) : 400)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSearching)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击背景区域时，完成所有正在编辑的笔记
            finishAllEditing()
        }
        .onChange(of: viewMode) { _, newValue in
            selectedTag = nil
            resetPagination()
            // 切换模式时，如果当前选中的分组不属于该模式，则切换到默认分组
            let currentGroup = noteManager.groups.first { $0.id == selectedGroupId }
            if newValue == .knowledge {
                if currentGroup?.isKnowledgeGroup != true {
                    selectedGroupId = NoteGroup.defaultKnowledgeId
                }
            } else if newValue == .all || newValue == .completed {
                if currentGroup?.isKnowledgeGroup == true {
                    selectedGroupId = NoteGroup.defaultId
                }
            }
            
            // 切换模式时通知窗口重新计算高度
            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
        }
        .onChange(of: selectedGroupId) { _, _ in
            selectedTag = nil
            resetPagination()
            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
        }
        .onChange(of: selectedTag) { _, _ in
            resetPagination()
            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
        }
        .onChange(of: searchText) { _, _ in
            resetPagination()
            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("floatingButtonConfigChanged"))) { _ in
            // 配置更改时更新默认分组
            let config = configManager.config
            if viewMode == .knowledge {
                selectedGroupId = config.defaultKnowledgeGroupId ?? NoteGroup.defaultKnowledgeId
            } else {
                selectedGroupId = config.defaultNoteGroupId ?? NoteGroup.defaultId
            }
        }
        .onChange(of: visibleNotes) { _, _ in
            // 可见笔记内容或数量变化时通知窗口重新计算高度
            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
        }
        .sheet(isPresented: $isShowingGroupManager) {
            GroupManagerView()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // 应用程序失去焦点时完成所有编辑
            finishAllEditing()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            // 窗口失去焦点时完成所有编辑
            finishAllEditing()
        }
    }
    
    private func finishAllEditing() {
        // 通过发送通知来完成所有正在编辑的笔记
        NotificationCenter.default.post(name: Notification.Name("FinishAllNoteEditing"), object: nil)
    }

    private var toolbarView: some View {
        HStack {
            HStack(spacing: 12) {
                // 列表按钮
                ToolbarButton(icon: "list.bullet", isActive: viewMode == .all || viewMode == .completed) {
                    withAnimation {
                        viewMode = .all
                    }
                }
                
                // 仅在列表或已完成模式下显示的按钮
                if viewMode == .all || viewMode == .completed {
                    // 加号按钮
                    if viewMode == .all {
                        ToolbarButton(icon: "plus", isActive: false) {
                            noteManager.addNewEmptyNote(groupId: selectedGroupId)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // 已完成按钮
                    ToolbarButton(icon: "checkmark", isActive: viewMode == .completed) {
                        withAnimation {
                            viewMode = viewMode == .completed ? .all : .completed
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // 剪切板按钮（仅非笔记专属模式显示）
                if !isNoteMode {
                    ToolbarButton(icon: "doc.on.clipboard", isActive: viewMode == .clipboard) {
                        withAnimation {
                            viewMode = viewMode == .clipboard ? .all : .clipboard
                        }
                    }
                }
                
                // 知识按钮 - 三态切换：all → knowledge → ai → all
                ToolbarButton(icon: viewMode == .ai ? "brain.head.profile" : "book", isActive: viewMode == .knowledge || viewMode == .ai) {
                    withAnimation {
                        switch viewMode {
                        case .knowledge:
                            viewMode = .ai
                        case .ai:
                            viewMode = .all
                        default:
                            viewMode = .knowledge
                        }
                    }
                }
                
                // AI 模式下的创建按钮
                if viewMode == .ai {
                    ToolbarButton(icon: "plus", isActive: false) {
                        noteManager.addNewAINote(groupId: selectedGroupId)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // 常用文件按钮（仅非笔记专属模式显示）
                if !isNoteMode {
                    ToolbarButton(icon: "folder.fill", isActive: viewMode == .favorites) {
                        withAnimation {
                            viewMode = viewMode == .favorites ? .all : .favorites
                        }
                    }
                }
                
                // 回收站按钮
                ToolbarButton(icon: "trash", isActive: viewMode == .trash) {
                    withAnimation {
                        viewMode = viewMode == .trash ? .all : .trash
                    }
                }
                
                // 搜索区域
                HStack(spacing: 8) {
                    ToolbarButton(icon: "magnifyingglass", isActive: isSearching) {
                        withAnimation(.spring()) {
                            isSearching.toggle()
                            if !isSearching {
                                searchText = ""
                            } else {
                                isSearchFocused = true
                            }
                            // 通知窗口宽度可能需要调整
                            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
                        }
                    }
                    
                    if isSearching {
                        TextField("搜索...", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .foregroundColor(.black)
                            .frame(width: 120)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                            )
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }
            .padding(8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(configManager.config.toolbarOpacity))
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            
            Spacer() // 确保工具栏左对齐
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var groupSelectorView: some View {
        let groups = noteManager.getSortedGroups(isKnowledgeGroup: viewMode == .knowledge)
            .filter { $0.id != NoteGroup.colorGroupId } // 过滤颜色列表分组
            
        let maxPerRow = 6
        let totalItems = groups.count
        let rowCount = max(0, (totalItems + maxPerRow - 1) / maxPerRow)
        
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 8) {
                    let startIndex = row * maxPerRow
                    let endIndex = min(startIndex + maxPerRow, totalItems)
                    
                    ForEach(startIndex..<endIndex, id: \.self) { index in
                        if index < groups.count {
                            let group = groups[index]
                            Button(action: {
                                withAnimation {
                                    selectedGroupId = group.id
                                    globalPasswordInput = ""
                                    globalPasswordError = false
                                    noteManager.resetAutoLockTimer()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    let mode = configManager.config.groupDisplayMode
                                    
                                    if mode == .iconOnly || mode == .both {
                                        Image(systemName: group.icon)
                                            .font(.system(size: 12))
                                    }
                                    
                                    if mode == .nameOnly || mode == .both {
                                        Text(group.name)
                                            .font(.system(size: 12, weight: selectedGroupId == group.id ? .bold : .regular))
                                            .lineLimit(1)
                                            .frame(maxWidth: 56)
                                    }
                                    
                                    if group.isLocked {
                                        Image(systemName: noteManager.isSessionUnlocked ? "lock.open.fill" : "lock.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(noteManager.isSessionUnlocked ? .green.opacity(0.8) : .orange.opacity(0.8))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selectedGroupId == group.id ? Color.white.opacity(configManager.config.groupOpacity) : Color.black.opacity(configManager.config.groupOpacity))
                                )
                                .foregroundColor(selectedGroupId == group.id ? .black : .white)
                                .overlay(
                                    selectedGroupId == group.id ?
                                    Capsule()
                                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                        .shadow(color: Color.white.opacity(0.8), radius: 2, x: 0, y: -1)
                                    : nil
                                )
                                .shadow(color: selectedGroupId == group.id ? Color.black.opacity(0.3) : Color.clear, radius: 3, x: 0, y: 2)
                                .shadow(color: selectedGroupId == group.id ? Color.white.opacity(0.7) : Color.clear, radius: 6, x: 0, y: -1)
                            }
                            .buttonStyle(.plain)
                            .overlay(
                                GroupRightClickOverlay(isLocked: group.isLocked, isSessionUnlocked: noteManager.isSessionUnlocked) {
                                    noteManager.isSessionUnlocked = false
                                }
                            )
                            .contextMenu {
                                if group.isPresetGroup {
                                    Button("管理分组") {
                                        isShowingGroupManager.toggle()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var noteListContentView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewMode == .clipboard {
                        ClipboardPreviewView()
                    } else if viewMode == .favorites {
                        FavoriteListContentView()
                    } else if viewMode == .trash {
                        TrashListView()
                    } else if noteManager.isGroupLocked(selectedGroupId) {
                        // 锁定分组：显示密码输入界面
                        VStack(spacing: 16) {
                            Spacer().frame(height: 40)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.gray)
                            Text("此分组已设置密码保护")
                                .foregroundColor(.black.opacity(0.7))
                                .font(.system(size: 14))
                            SecureField("输入密码以解锁", text: $globalPasswordInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                                .onSubmit {
                                    if noteManager.verifyGlobalPassword(globalPasswordInput) {
                                        globalPasswordInput = ""
                                        globalPasswordError = false
                                    } else {
                                        globalPasswordError = true
                                    }
                                }
                            if globalPasswordError {
                                Text("密码错误")
                                    .foregroundColor(.red)
                                    .font(.system(size: 12))
                            }
                            Button("解锁") {
                                if noteManager.verifyGlobalPassword(globalPasswordInput) {
                                    globalPasswordInput = ""
                                    globalPasswordError = false
                                } else {
                                    globalPasswordError = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.95))
                        .cornerRadius(12)
                    } else {
                        ForEach(Array(visibleNotes.enumerated()), id: \.element.id) { index, note in
                            if note.isAI {
                                AINoteItemView(note: note, onDelete: {
                                    DispatchQueue.main.async {
                                        noteManager.deleteNote(id: note.id)
                                    }
                                })
                                .id(note.id)
                                .onAppear {
                                    if index >= visibleNotes.count - 3 {
                                        loadMoreNotes()
                                    }
                                }
                            } else {
                                NoteItemView(note: note, selectedTag: selectedTag, onDelete: {
                                    DispatchQueue.main.async {
                                        noteManager.deleteNote(id: note.id)
                                    }
                                }, onToggle: {
                                    noteManager.toggleCompleted(id: note.id)
                                }, onTagClick: { clickedTag in
                                    if selectedTag == clickedTag {
                                        selectedTag = nil
                                    } else {
                                        selectedTag = clickedTag
                                    }
                                })
                                .id(note.id)
                                .onAppear {
                                    if index >= visibleNotes.count - 3 {
                                        loadMoreNotes()
                                    }
                                }
                            }
                        }
                        
                        if hasMoreNotes {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.8)))
                                Text("正在加载更多 (\(visibleNotes.count)/\(filteredNotes.count))...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .onAppear {
                                loadMoreNotes()
                            }
                        }
                    }
                }
                .background(Color.black.opacity(0.001))
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(key: ViewSizeKey.self, value: geometry.size)
                    }
                )
                .padding(.top, 8) // 添加顶部内边距，防止阴影和边框被遮挡
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .onPreferenceChange(ViewSizeKey.self) { _ in
                // 当内部内容大小变化时，通知窗口调整高度
                NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
            }
            .frame(maxHeight: configManager.config.noteWindowHeight - 80)
            .onChange(of: filteredNotes.count) { oldValue, newValue in
                if newValue > oldValue, let firstNote = filteredNotes.first {
                    withAnimation {
                        proxy.scrollTo(firstNote.id, anchor: .top)
                    }
                }
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20))
        }
    }
}

struct GroupManagerView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var noteManager = NoteManager.shared
    @StateObject private var configManager = FloatingButtonConfigManager.shared
    @State private var newGroupName = ""
    @State private var newGroupIcon = "folder"
    @State private var isKnowledgeGroup = false
    @State private var showIconPicker = false
    
    private var isGroupLimitReached: Bool {
        noteManager.getSortedGroups(isKnowledgeGroup: isKnowledgeGroup).count >= 6
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("notes.manageGroups"))
                    .font(.headline)
                Spacer()
                Button(L10n.tr("common.done")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            List {
                Section("分组设置") {
                    HStack {
                        Text(L10n.tr("notes.displayMode"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { configManager.config.groupDisplayMode },
                            set: { configManager.updateGroupDisplayMode($0) }
                        )) {
                            ForEach(FloatingButtonConfig.GroupDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)
                    }
                    
                    HStack {
                        Text(L10n.tr("notes.defaultNoteGroup"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { configManager.config.defaultNoteGroupId ?? NoteGroup.defaultId },
                            set: { configManager.updateDefaultNoteGroupId($0) }
                        )) {
                            ForEach(noteManager.getSortedGroups(isKnowledgeGroup: false)) { group in
                                Text(group.name).tag(group.id)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)
                    }
                    
                    HStack {
                        Text(L10n.tr("notes.defaultKnowledgeGroup"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { configManager.config.defaultKnowledgeGroupId ?? NoteGroup.defaultKnowledgeId },
                            set: { configManager.updateDefaultKnowledgeGroupId($0) }
                        )) {
                            ForEach(noteManager.getSortedGroups(isKnowledgeGroup: true)) { group in
                                Text(group.name).tag(group.id)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)
                    }
                }
                
                Section("新建分组") {
                    VStack(spacing: 10) {
                        HStack {
                            Button(action: { showIconPicker.toggle() }) {
                                Image(systemName: newGroupIcon)
                                    .font(.system(size: 20))
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isGroupLimitReached)
                            .popover(isPresented: $showIconPicker) {
                                SymbolPickerView(selectedSymbol: $newGroupIcon)
                                    .frame(width: 360, height: 400)
                            }
                            
                            TextField(isGroupLimitReached ? "分组数量已达上限(最多6个)" : "分组名称", text: $newGroupName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isGroupLimitReached)
                            Button(L10n.tr("common.add")) {
                                if !newGroupName.isEmpty && !isGroupLimitReached {
                                    noteManager.addGroup(name: newGroupName, icon: newGroupIcon.isEmpty ? "folder" : newGroupIcon, isKnowledge: isKnowledgeGroup)
                                    newGroupName = ""
                                    newGroupIcon = "folder"
                                }
                            }
                            .disabled(newGroupName.isEmpty || isGroupLimitReached)
                        }
                        
                        if isGroupLimitReached {
                            Text("当前分类分组已达上限（最多6个，含预设分组）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Toggle("知识库分组", isOn: $isKnowledgeGroup)
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Section("现有分组") {
                    ForEach(noteManager.getSortedGroups(isKnowledgeGroup: isKnowledgeGroup)) { group in
                        GroupRow(group: group)
                    }
                    .onMove { source, destination in
                        noteManager.moveGroup(from: source, to: destination, isKnowledgeGroup: isKnowledgeGroup)
                    }
                }
            }
        }
        .frame(width: 400, height: 600)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}

struct GroupRow: View {
    @State var group: NoteGroup
    @State private var isEditing = false
    @State private var editedName: String
    @State private var editedIcon: String
    @State private var showIconPicker = false
    @State private var showLockPasswordSheet = false
    @State private var lockPwdInput = ""
    @State private var lockPwdError = false
    @StateObject private var noteManager = NoteManager.shared
    
    init(group: NoteGroup) {
        self.group = group
        _editedName = State(initialValue: group.name)
        _editedIcon = State(initialValue: group.icon)
    }
    
    var body: some View {
        HStack {
            if isEditing {
                Button(action: { showIconPicker.toggle() }) {
                    Image(systemName: editedIcon)
                        .font(.system(size: 16))
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showIconPicker) {
                    SymbolPickerView(selectedSymbol: $editedIcon)
                        .frame(width: 360, height: 400)
                }
                
                TextField("名称", text: $editedName)
                    .textFieldStyle(.roundedBorder)
                Button(L10n.tr("common.save")) {
                    var updatedGroup = group
                    updatedGroup.name = editedName
                    updatedGroup.icon = editedIcon.isEmpty ? "folder" : editedIcon
                    noteManager.updateGroup(updatedGroup)
                    group = updatedGroup
                    isEditing = false
                }
            } else {
                Image(systemName: group.icon)
                    .frame(width: 20)
                VStack(alignment: .leading) {
                    Text(group.name)
                    if group.isKnowledgeGroup {
                        Text(L10n.tr("notes.knowledgeBase"))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                Spacer()
                if !group.isPresetGroup {
                    // 活动分组标记（仅显示，不可切换）
                    if group.isActivityGroup {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                            .help("活动记录分组")
                    }
                    
                    // 锁定开关按钮
                    Button(action: {
                        lockPwdInput = ""
                        lockPwdError = false
                        showLockPasswordSheet = true
                    }) {
                        Image(systemName: group.isLocked ? "lock.fill" : "lock.open")
                            .foregroundColor(group.isLocked ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(group.isLocked ? "取消锁定" : "设为锁定")
                    .disabled(!noteManager.hasGlobalPassword)
                    
                    Button(action: { isEditing = true }) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                }
                
                if !group.isPresetGroup {
                    Button(role: .destructive) {
                        noteManager.deleteGroup(id: group.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showLockPasswordSheet) {
            VStack(spacing: 16) {
                Text(group.isLocked ? "取消锁定" : "锁定分组")
                    .font(.headline)
                Text("请输入全局密码")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                SecureField("密码", text: $lockPwdInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if noteManager.verifyGlobalPassword(lockPwdInput) {
                            noteManager.toggleGroupLock(groupId: group.id)
                            if let updated = noteManager.groups.first(where: { $0.id == group.id }) {
                                group = updated
                            }
                            showLockPasswordSheet = false
                        } else {
                            lockPwdError = true
                        }
                    }
                if lockPwdError {
                    Text("密码错误")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                HStack {
                    Button("取消") {
                        showLockPasswordSheet = false
                    }
                    Spacer()
                    Button("确认") {
                        if noteManager.verifyGlobalPassword(lockPwdInput) {
                            noteManager.toggleGroupLock(groupId: group.id)
                            if let updated = noteManager.groups.first(where: { $0.id == group.id }) {
                                group = updated
                            }
                            showLockPasswordSheet = false
                        } else {
                            lockPwdError = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 280)
        }
    }
}

// MARK: - Trash List View
struct TrashListView: View {
    @StateObject private var noteManager = NoteManager.shared
    @State private var showConfirmEmpty = false
    
    private var trashNotes: [Note] {
        noteManager.notes.filter { $0.isDeleted }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("notes.trash"))
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(trashNotes.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                if !trashNotes.isEmpty {
                    Button(action: { showConfirmEmpty = true }) {
                        Text(L10n.tr("notes.emptyTrash"))
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .alert(L10n.tr("notes.confirmEmptyTrash"), isPresented: $showConfirmEmpty) {
                        Button(L10n.tr("common.cancel"), role: .cancel) {}
                        Button(L10n.tr("notes.emptyTrash"), role: .destructive) {
                            noteManager.emptyTrash()
                        }
                    } message: {
                        Text(L10n.tr("notes.emptyTrashWarning"))
                    }
                }
            }
            .padding(.horizontal, 4)
            
            if trashNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.3))
                    Text(L10n.tr("notes.trashEmpty"))
                        .foregroundColor(.white.opacity(0.6))
                        .italic()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(trashNotes) { note in
                            TrashItemRow(note: note)
                        }
                    }
                }
                .frame(height: 340)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct TrashItemRow: View {
    let note: Note
    @State private var isHovered = false
    @StateObject private var noteManager = NoteManager.shared
    
    private var groupName: String {
        noteManager.groups.first { $0.id == note.groupId }?.name ?? "未知分组"
    }
    
    private var deletedTimeText: String {
        guard let deletedAt = note.deletedAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: deletedAt, relativeTo: Date())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(groupName)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(deletedTimeText)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                
                if isHovered {
                    HStack(spacing: 8) {
                        Button(action: {
                            noteManager.restoreNote(id: note.id)
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr("notes.restoreNote"))
                        
                        Button(action: {
                            noteManager.permanentDeleteNote(id: note.id)
                        }) {
                            Image(systemName: "trash.slash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr("notes.permanentlyDelete"))
                    }
                    .transition(.opacity)
                }
            }
            
            Text(note.content)
                .lineLimit(3)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.black.opacity(isHovered ? 0.3 : 0.15))
        .cornerRadius(12)
        .contextMenu {
            Button(L10n.tr("notes.restoreNote")) {
                noteManager.restoreNote(id: note.id)
            }
            Button(L10n.tr("notes.permanentlyDelete"), role: .destructive) {
                noteManager.permanentDeleteNote(id: note.id)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct GroupRightClickOverlay: NSViewRepresentable {
    let isLocked: Bool
    let isSessionUnlocked: Bool
    let onRightClick: () -> Void
    
    func makeNSView(context: Context) -> RightClickPassthroughView {
        let view = RightClickPassthroughView()
        view.onRightClick = onRightClick
        view.shouldHandle = isLocked && isSessionUnlocked
        return view
    }
    
    func updateNSView(_ nsView: RightClickPassthroughView, context: Context) {
        nsView.onRightClick = onRightClick
        nsView.shouldHandle = isLocked && isSessionUnlocked
    }
    
    class RightClickPassthroughView: NSView {
        var onRightClick: (() -> Void)?
        var shouldHandle = false
        
        override func rightMouseDown(with event: NSEvent) {
            if shouldHandle {
                DispatchQueue.main.async { [weak self] in
                    self?.onRightClick?()
                }
            } else {
                super.rightMouseDown(with: event)
            }
        }
        
        override func hitTest(_ point: NSPoint) -> NSView? {
            // 左键点击透传给下层 Button
            guard let event = NSApp.currentEvent else { return nil }
            if event.type == .rightMouseDown {
                return super.hitTest(point)
            }
            return nil
        }
    }
}

struct ViewSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct ToolbarButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.white.opacity(0.3) : Color.clear)
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .shadow(radius: 2)
    }
}

struct ClipboardContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ClipboardPreviewView: View {
    @StateObject private var clipboardManager = ClipboardManager.shared
    @StateObject private var configManager = FloatingButtonConfigManager.shared
    @State private var listHeight: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("clipboard.history"))
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("上限: \(configManager.config.clipboardHistoryLimit)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 4)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if clipboardManager.history.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.3))
                            Text(L10n.tr("clipboard.noRecords"))
                                .foregroundColor(.white.opacity(0.6))
                                .italic()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(clipboardManager.history) { item in
                            ClipboardItemRow(item: item)
                        }
                    }
                }
                .padding(.trailing, 2) // Optional: avoid scrollbar overlap if visible
            }
            .frame(height: 340) // Fixed height as requested
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.blue)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    @State private var isHovered = false
    @State private var showToast = false
    @State private var showCopiedToast = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(.white.opacity(0.7))
                
                Text(typeName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                if isHovered {
                    HStack(spacing: 12) {
                        Button(action: {
                            // 先复制到剪切板，不改变排序
                            ClipboardManager.shared.copyToClipboard(item, shouldAddToHistory: false)
                            withAnimation {
                                showCopiedToast = true
                            }
                            // toast 消失后，再带动画移到顶部
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showCopiedToast = false
                                }
                                // 延迟一小段再排序，让 toast 消失动画完成
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        ClipboardManager.shared.moveToTop(item)
                                    }
                                }
                            }
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr("clipboard.copyToClipboard"))
                        
                        if item.type == .text {
                            Button(action: {
                                if let text = item.stringValue {
                                    NoteManager.shared.addNote(content: text)
                                    withAnimation {
                                        showToast = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation {
                                            showToast = false
                                        }
                                    }
                                }
                            }) {
                                Image(systemName: "plus.square")
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.tr("clipboard.saveAsNote"))
                        }
                    }
                    .transition(.opacity)
                }
            }
            
            Group {
                if item.type == .image, let image = item.imageValue {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 150)
                        .cornerRadius(4)
                } else if let text = item.stringValue {
                    Text(text)
                        .lineLimit(3)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                } else {
                    Text(L10n.tr("clipboard.cannotPreview"))
                        .font(.caption)
                        .italic()
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.black.opacity(isHovered ? 0.3 : 0.15))
        .cornerRadius(12)
        .overlay(
            Group {
                if showCopiedToast {
                    Text(L10n.tr("clipboard.copiedWillPin"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .transition(.scale.combined(with: .opacity))
                } else if showToast {
                    Text(L10n.tr("clipboard.savedAsNote"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            },
            alignment: .center
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private var iconName: String {
        switch item.type {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        case .other: return "questionmark.circle"
        }
    }
    
    private var typeName: String {
        switch item.type {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件路径"
        case .other: return "其他"
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// 隐藏 TextEditor 滚动条轨道的修饰符
struct HideScrollIndicators: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                DispatchQueue.main.async {
                    if let scrollView = findScrollView(in: NSApp.keyWindow?.contentView) {
                        scrollView.scrollerStyle = .overlay
                        scrollView.hasVerticalScroller = true
                        scrollView.hasHorizontalScroller = false
                        scrollView.verticalScroller?.alphaValue = 0
                    }
                }
            }
    }
    
    private func findScrollView(in view: NSView?) -> NSScrollView? {
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
}

extension View {
    func hideScrollIndicators() -> some View {
        modifier(HideScrollIndicators())
    }
}
