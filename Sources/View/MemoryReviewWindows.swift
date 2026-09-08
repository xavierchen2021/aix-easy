import Cocoa
import SwiftUI

class MemoryReviewReminderWindow: NSPanel {
    var onStartReview: (() -> Void)?

    init(message: String) {
        let frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        let rootView = MemoryReviewReminderView(message: message) { [weak self] in
            self?.onStartReview?()
            self?.orderOut(nil)
        }
        let hosting = NSHostingView(rootView: rootView)

        isFloatingPanel = true
        level = .statusBar
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = hosting
    }

    func showBottomRight() {
        guard let screen = NSScreen.main else {
            makeKeyAndOrderFront(nil)
            return
        }

        let visible = screen.visibleFrame
        let x = visible.maxX - frame.width - 20
        let y = visible.minY + 20
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
    }
}

private struct MemoryReviewReminderView: View {
    let message: String
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.orange)
                Text("复习提醒")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack {
                Spacer()
                Button("开始复习") {
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
        )
    }
}

class MemoryReviewDialogWindow: NSWindow {
    static let defaultSize = NSSize(width: 760, height: 520)

    init() {
        let winSize = Self.defaultSize
        let frame = NSRect(origin: .zero, size: winSize)

        super.init(contentRect: frame,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered,
                   defer: false)

        title = "记忆复习"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 700, height: 440)

        contentViewController = NSHostingController(rootView: MemoryReviewDialogView())

        // 强制应用指定尺寸，避免 SwiftUI 首帧尺寸塌陷
        setContentSize(winSize)
        setFrame(NSRect(origin: frame.origin, size: winSize), display: true)
        center()
    }
}

private struct MemoryReviewDialogView: View {
    @StateObject private var noteManager = NoteManager.shared
    @StateObject private var memoryManager = MemoryManager.shared

    @State private var currentEntry: MemoryEntry? = nil
    @State private var question: String = ""
    @State private var answer: String = ""
    @State private var feedback: String = ""
    @State private var isEvaluating: Bool = false
    @State private var isNoteVisible: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("语义复习")
                .font(.system(size: 16, weight: .semibold))

            if let entry = currentEntry,
               let note = noteManager.notes.first(where: { $0.id == entry.noteId }) {
                Text("记忆线索：\(entry.palaceCue)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text(question)
                    .font(.system(size: 13, weight: .medium))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))

                TextEditor(text: $answer)
                    .frame(height: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))

                HStack {
                    Text("提交回答后将自动语义评估并安排间隔")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()

                    Button("已掌握") {
                        markAsMastered(entry: entry)
                    }
                    .disabled(isEvaluating)
                    .buttonStyle(.bordered)
                    .help("跳过评估，60 天后再复习")

                    Button("提交回答") {
                        evaluateAnswer(entry: entry, note: note)
                    }
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEvaluating)
                    .buttonStyle(.borderedProminent)
                }

                if isEvaluating {
                    ProgressView("语义评估中...")
                        .font(.system(size: 12))
                }

                if !feedback.isEmpty {
                    Text(feedback)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Text("知识原文")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(isNoteVisible ? "隐藏" : "显示") {
                        isNoteVisible.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if isNoteVisible {
                    Text(note.content)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                } else {
                    Text("内容已隐藏，点击“显示”后查看")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("当前没有到期复习条目")
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .onAppear {
            Task {
                await loadNext()
            }
        }
    }

    private func loadNext() async {
        let inProgress = noteManager.notes.filter { $0.isInProgress && !$0.isDeleted }
        let candidates = await memoryManager.dueEntriesSortedSmart(by: inProgress)
        currentEntry = candidates.first
        answer = ""
        feedback = ""
        isNoteVisible = false

        if let entry = currentEntry,
           let note = noteManager.notes.first(where: { $0.id == entry.noteId }) {
            let context = inProgress.map { $0.content }.joined(separator: "\n")
            question = await AIService.shared.generateMemoryQuestion(noteContent: note.content, taskContext: context)
        } else {
            question = ""
        }
    }

    private func evaluateAnswer(entry: MemoryEntry, note: Note) {
        let input = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isEvaluating = true
        Task {
            let inProgress = noteManager.notes.filter { $0.isInProgress && !$0.isDeleted }
            let context = inProgress.map { $0.content }.joined(separator: "\n")
            let result = await AIService.shared.evaluateMemoryAnswer(
                noteContent: note.content,
                question: question,
                answer: input,
                taskContext: context
            )

            memoryManager.scheduleAfterReview(entryId: entry.id, quality: result.quality)
            feedback = result.feedback
            isEvaluating = false

            try? await Task.sleep(nanoseconds: 700_000_000)
            await loadNext()
        }
    }

    private func markAsMastered(entry: MemoryEntry) {
        memoryManager.markAsMastered(entryId: entry.id)
        feedback = "✅ 已标记为掌握，60 天后再复习"
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await loadNext()
        }
    }
}
