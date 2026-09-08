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
        
        let config = FloatingButtonConfigManager.shared.config
        
        guard !config.aiApiKey.isEmpty, !config.aiUrl.isEmpty else {
            self.currentTranslation?.translatedText = "请先在设置中配置 AI API Key 和接口地址"
            self.isTranslating = false
            return
        }
        
        // 判断翻译方向
        let chineseCount = trimmed.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let isChinese = chineseCount > trimmed.count / 3
        let targetLanguage = isChinese ? "English" : "中文"
        
        let systemPrompt = "你是一个专业的翻译助手。请将以下文本翻译为\(targetLanguage)。只输出翻译结果，不要添加任何解释或前缀。"
        
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": trimmed]
        ]
        
        var urlString = config.aiUrl
        if !urlString.hasSuffix("/") { urlString += "/" }
        urlString += "chat/completions"
        
        guard let url = URL(string: urlString) else {
            self.currentTranslation?.translatedText = "无效的 AI 接口地址"
            self.isTranslating = false
            return
        }
        
        let requestBody: [String: Any] = [
            "model": config.aiModel,
            "messages": messages.map { $0 as [String: Any] },
            "stream": true
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            self.currentTranslation?.translatedText = "请求构建失败"
            self.isTranslating = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.aiApiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        
        // 使用 delegate 实现真正的 SSE 流式输出
        let delegate = TranslationStreamDelegate(
            onChunk: { [weak self] chunk in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.currentTranslation?.translatedText += chunk
                }
            },
            onComplete: { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isTranslating = false
                    // 保存到历史
                    if let record = self.currentTranslation,
                       !record.translatedText.isEmpty,
                       !record.translatedText.hasPrefix("翻译失败") {
                        self.translationHistory.insert(record, at: 0)
                        if self.translationHistory.count > 200 {
                            self.translationHistory = Array(self.translationHistory.prefix(200))
                        }
                        self.saveHistory()
                    }
                }
            },
            onError: { [weak self] errorMsg in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isTranslating = false
                    if self.currentTranslation?.translatedText.isEmpty == true {
                        self.currentTranslation?.translatedText = "翻译失败: \(errorMsg)"
                    }
                }
            }
        )
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        self.activeSession = session
        self.activeTask = task
        task.resume()
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
