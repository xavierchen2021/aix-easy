import SwiftUI
import AppKit

// MARK: - 翻译弹窗窗口

class TranslationPopupWindow: NSWindow {
    init() {
        let contentView = TranslationPopupView()
        let hostingController = NSHostingController(rootView: contentView)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.contentViewController = hostingController
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.backgroundColor = .clear
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 320, height: 200)
        self.hasShadow = true
        
        // 居中显示
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 210
            let y = screenFrame.midY - 150
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 翻译弹窗视图

struct TranslationPopupView: View {
    @StateObject private var manager = TranslationManager.shared
    @State private var editableText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题栏
            HStack {
                Image(systemName: "translate")
                    .foregroundColor(.blue)
                Text("翻译")
                    .font(.headline)
                Spacer()
                if manager.isTranslating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Button(action: {
                    // 关闭翻译弹窗
                    NSApp.windows.first { $0 is TranslationPopupWindow }?.orderOut(nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            
            Divider()
            
            // 原文（可编辑输入框）
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("原文")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TTSSpeakButton(text: editableText, language: .auto)
                }
                TextEditor(text: $editableText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                    .onSubmit {
                        retranslate()
                    }
                HStack {
                    Spacer()
                    Button("重新翻译") {
                        retranslate()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // 翻译结果
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("翻译")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TTSSpeakButton(text: manager.currentTranslation?.translatedText ?? "", language: .auto)
                    if manager.isTranslating {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                    Spacer()
                    Button(action: {
                        if let record = manager.currentTranslation {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.translatedText, forType: .string)
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("复制翻译结果")
                    .disabled(manager.currentTranslation?.translatedText.isEmpty ?? true)
                    
                    Button(action: {
                        if let record = manager.currentTranslation {
                            // 1. 复制翻译结果到剪贴板
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.translatedText, forType: .string)
                            
                            // 2. 隐藏翻译窗口
                            NSApp.windows.first { $0 is TranslationPopupWindow }?.orderOut(nil)
                            
                            // 3. 激活之前的应用并延迟执行 Cmd+V 粘贴
                            if let previousApp = manager.previousActiveApp {
                                previousApp.activate()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    let _ = HotkeyExecutor.execute(hotkey: "Cmd+V")
                                }
                            } else {
                                // 如果没有记录到之前的应用，直接尝试粘贴
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    let _ = HotkeyExecutor.execute(hotkey: "Cmd+V")
                                }
                            }
                        }
                    }) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("替换原文")
                    .disabled(manager.currentTranslation?.translatedText.isEmpty ?? true)
                }
                ScrollView {
                    Text(manager.currentTranslation?.translatedText ?? "")
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeIn(duration: 0.05), value: manager.currentTranslation?.translatedText)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 320, minHeight: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: manager.currentTranslation?.originalText) { _, newValue in
            if let text = newValue {
                editableText = text
            }
        }
        .onAppear {
            editableText = manager.currentTranslation?.originalText ?? ""
        }
    }
    
    private func retranslate() {
        let text = editableText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        manager.retranslate(text: text)
    }
}
