import Foundation
import AppKit

@MainActor
class TranslationManager: ObservableObject {
    static let shared = TranslationManager()
    
    @Published var translationHistory: [TranslationRecord] = []
    @Published var currentTranslation: TranslationRecord?
    @Published var isTranslating = false
    
    private let store = AppDatabase.shared.settingsStore
    private let historyKey = "translation_history"
    private var activeSession: URLSession?
    private var activeTask: URLSessionDataTask?
    var previousActiveApp: NSRunningApplication?
    
    private init() {
        loadHistory()
    }
    
    /// 触发翻译：模拟 Cmd+C → 读剪贴板 → 立即显示弹窗 → 流式翻译
    func triggerTranslation() {
        // 保存当前活动应用
        previousActiveApp = NSWorkspace.shared.frontmostApplication
        
        // 保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount
        
        // 模拟 Cmd+C 复制选中文本
        let _ = HotkeyExecutor.execute(hotkey: "Cmd+C")
        
        // 延迟读取剪贴板（等待复制完成）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            let currentChangeCount = pasteboard.changeCount
            
            // 检查剪贴板是否变化
            guard currentChangeCount != previousChangeCount,
                  let text = pasteboard.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // 恢复剪贴板
                if let prev = previousContent {
                    pasteboard.clearContents()
                    pasteboard.setString(prev, forType: .string)
                }
                return
            }
            
            // 恢复剪贴板原内容
            if let prev = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(prev, forType: .string)
            }
            
            self.translate(text: text)
        }
    }
    
    /// 执行翻译：立即显示弹窗，流式输出翻译结果
    private func translate(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // 取消之前的翻译
        cancelCurrentTranslation()
        
        let record = TranslationRecord(
            originalText: trimmed,
            translatedText: "",
            timestamp: Date()
        )
        currentTranslation = record
        isTranslating = true
        
        // 立即显示翻译弹窗
        NotificationCenter.default.post(name: .showTranslationPopup, object: nil)
        
        self.currentTranslation?.translatedText = "AI 接口已移除"
        self.isTranslating = false
        return
    }
    
    func cancelCurrentTranslation() {
        activeTask?.cancel()
        activeTask = nil
        activeSession?.invalidateAndCancel()
        activeSession = nil
    }
    
    /// 重新翻译（用户编辑原文后触发）
    func retranslate(text: String) {
        translate(text: text)
    }
    
    // MARK: - 历史记录持久化
    
    private func loadHistory() {
        guard let str = store.loadConfig(key: historyKey),
              let data = str.data(using: .utf8),
              let records = try? JSONDecoder().decode([TranslationRecord].self, from: data) else { return }
        translationHistory = records
    }
    
    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(translationHistory),
              let str = String(data: data, encoding: .utf8) else { return }
        try? store.saveConfig(key: historyKey, value: str)
    }
    
    func clearHistory() {
        translationHistory.removeAll()
        saveHistory()
    }
    
    func deleteRecord(id: UUID) {
        translationHistory.removeAll { $0.id == id }
        saveHistory()
    }
}

// MARK: - SSE 流式解析 Delegate

private class TranslationStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onChunk: @Sendable (String) -> Void
    private let onComplete: @Sendable () -> Void
    private let onError: @Sendable (String) -> Void
    private var buffer = ""
    
    init(onChunk: @escaping @Sendable (String) -> Void,
         onComplete: @escaping @Sendable () -> Void,
         onError: @escaping @Sendable (String) -> Void) {
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text
        
        // 逐行解析 SSE
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
            buffer = String(buffer[newlineRange.upperBound...])
            
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("data: ") {
                let jsonStr = String(trimmedLine.dropFirst(6))
                if jsonStr == "[DONE]" {
                    onComplete()
                    return
                }
                if let jsonData = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    onChunk(content)
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error {
            if (error as NSError).code != NSURLErrorCancelled {
                onError(error.localizedDescription)
            }
        } else {
            // 处理 buffer 中剩余数据
            let trimmedBuffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBuffer.isEmpty {
                // 尝试作为非流式 JSON 解析
                if let data = trimmedBuffer.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    onChunk(content)
                }
            }
            onComplete()
        }
    }
}

// MARK: - 翻译记录模型

struct TranslationRecord: Identifiable, Codable {
    let id: UUID
    var originalText: String
    var translatedText: String
    var timestamp: Date
    
    init(id: UUID = UUID(), originalText: String, translatedText: String, timestamp: Date) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.timestamp = timestamp
    }
}

// MARK: - 通知名

extension Notification.Name {
    static let showTranslationPopup = Notification.Name("showTranslationPopup")
}
