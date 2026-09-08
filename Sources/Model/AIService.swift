import Foundation

/// AI 聊天服务 — 支持 OpenAI 兼容接口和 opencode ACP 协议的流式输出
@MainActor
class AIService: ObservableObject {
    static let shared = AIService()
    
    /// ACP 连接状态
    enum ACPStatus: String {
        case disconnected = "未连接"
        case connecting = "连接中..."
        case connected = "已连接"

        var localizedName: String {
            switch self {
            case .disconnected: return L10n.tr("acp.disconnected")
            case .connecting: return L10n.tr("acp.connecting")
            case .connected: return L10n.tr("acp.connected")
            }
        }
    }
    
    /// ACP 连接状态（UI 可观察）
    @Published var acpStatus: ACPStatus = .disconnected
    
    /// 每个 sessionId 对应的消息历史
    private var sessions: [String: [[String: String]]] = [:]
    
    /// 当前正在进行的流式任务 (HTTP)
    private var activeStreams: [String: URLSessionDataTask] = [:]
    
    /// ACP 连接管理（手动 JSON-RPC 实现）
    private var acpProcess: Process?
    private var acpStdinPipe: Pipe?
    private var acpStdoutPipe: Pipe?
    private var acpSessionId: String?
    private var acpReadTask: Task<Void, Never>?
    private var acpRequestId: Int = 0
    private var acpPendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var acpOnChunk: (@Sendable (String) -> Void)?
    /// 连接代次标识，用于忽略旧连接的退出回调
    private var acpConnectionToken: UUID = UUID()
    
    /// ACP 完成回调（等 chunks 全部到达后调用）
    private var acpOnComplete: (@Sendable () -> Void)?
    private var acpChunkTimer: Timer?
    /// 标记 ACP 是否正在处理请求
    private var acpBusy = false
    /// ACP 最后活动时间（用于检测会话过期）
    private var acpLastActivityTime: Date?
    /// ACP 会话空闲超时（秒）
    private static let acpIdleTimeout: TimeInterval = 300 // 5 分钟
    
    /// ACP 连接保活相关
    private var shouldMaintainConnection: Bool = false  // 是否应保持连接（手动启动或自动启动时为 true）
    private var acpReconnectCount: Int = 0              // 当前连续重连次数
    private static let acpMaxReconnect: Int = 5         // 最大重连次数
    private var acpHealthTimer: Timer?                  // 健康检查定时器
    private var acpReconnecting: Bool = false            // 是否正在重连中
    
    private init() {}
    
    /// 从笔记内容解析所有问答对，构建完整的消息历史
    private func parseMessagesFromContent(_ content: String) -> [[String: String]] {
        var messages: [[String: String]] = []
        
        // 兼容"我："和"问："两种前缀
        let separator = content.contains("我：") ? "我：" : "问："
        let parts = content.components(separatedBy: separator)
        
        for (index, part) in parts.enumerated() {
            if index == 0 { continue } // 第一个空部分跳过
            
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // 兼容旧格式"答："分隔
            if let answerRange = trimmed.range(of: "\n答：") {
                let question = String(trimmed[trimmed.startIndex..<answerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let answer = String(trimmed[answerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !question.isEmpty { messages.append(["role": "user", "content": question]) }
                if !answer.isEmpty { messages.append(["role": "assistant", "content": answer]) }
            } else if let doubleNewline = trimmed.range(of: "\n\n") {
                // 新格式：问题行 + \n\n + AI 回答
                let question = String(trimmed[trimmed.startIndex..<doubleNewline.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let answer = String(trimmed[doubleNewline.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !question.isEmpty { messages.append(["role": "user", "content": question]) }
                if !answer.isEmpty { messages.append(["role": "assistant", "content": answer]) }
            } else {
                // 只有问题，没有答案
                if !trimmed.isEmpty { messages.append(["role": "user", "content": trimmed]) }
            }
        }
        
        return messages
    }
    
    /// 提取笔记内容中最后一个"我："后面的内容作为用户最新问题
    func extractLastQuestion(from content: String) -> String? {
        // 兼容"我："和"问："两种前缀
        let prefix = content.contains("我：") ? "我：" : "问："
        guard let lastRange = content.range(of: prefix, options: .backwards) else { return nil }
        // 问题是从 prefix 结束到第一个 \n\n 之前
        let rest = String(content[lastRange.upperBound...])
        let question: String
        if let end = rest.range(of: "\n\n") {
            question = String(rest[rest.startIndex..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            question = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return question.isEmpty ? nil : question
    }
    
    /// 发送问题并流式接收回答
    /// - Parameters:
    ///   - noteContent: 完整笔记内容（用于解析历史消息）
    ///   - sessionId: 会话 ID
    ///   - onChunk: 每收到一段文本时的回调
    ///   - onComplete: 完成时的回调
    ///   - onError: 出错时的回调
    func sendQuestion(
        noteContent: String,
        sessionId: String,
        onSessionReady: (@Sendable (String) -> Void)? = nil,
        onChunk: @escaping @Sendable (String) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        let configManager = FloatingButtonConfigManager.shared
        let config = configManager.config
        
        // 根据 AI 模式路由
        if config.aiMode == .opencode {
            sendViaOpencode(
                noteContent: noteContent,
                sessionId: sessionId,
                model: config.opencodeModel,
                onSessionReady: onSessionReady,
                onChunk: onChunk,
                onComplete: onComplete,
                onError: onError
            )
            return
        }
        
        // --- API 模式 —— 原有逻辑 ---
        guard !config.aiApiKey.isEmpty else {
            onError("请先在设置中配置 AI API Key")
            return
        }
        
        guard !config.aiUrl.isEmpty else {
            onError("请先在设置中配置 AI 接口地址")
            return
        }
        
        // 从笔记内容解析完整消息历史
        var messages = parseMessagesFromContent(noteContent)
        
        // 插入系统提示词
        if !config.aiSystemPrompt.isEmpty {
            messages.insert(["role": "system", "content": config.aiSystemPrompt], at: 0)
        }
        
        guard !messages.isEmpty else {
            onError("未找到有效的问题内容")
            return
        }
        
        // 构建 API URL
        var urlString = config.aiUrl
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "chat/completions"
        
        guard let url = URL(string: urlString) else {
            onError("无效的 AI 接口地址")
            return
        }
        
        // 构建请求体
        let requestBody: [String: Any] = [
            "model": config.aiModel,
            "messages": messages.map { $0 as [String: Any] },
            "stream": true
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            onError("请求构建失败")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.aiApiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        
        // 使用 URLSession delegate 处理流式数据
        let delegate = StreamDelegate(
            onChunk: onChunk,
            onComplete: { [weak self] in
                Task { @MainActor in
                    self?.activeStreams.removeValue(forKey: sessionId)
                    onComplete()
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.activeStreams.removeValue(forKey: sessionId)
                    onError(error)
                }
            }
        )
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        activeStreams[sessionId] = task
        task.resume()
    }
    
    /// 取消指定会话的流式请求
    func cancelStream(sessionId: String) {
        // 取消 HTTP 流
        activeStreams[sessionId]?.cancel()
        activeStreams.removeValue(forKey: sessionId)
        // 标记 ACP 不忙
        acpBusy = false
    }
    
    /// 检查会话是否正在流式输出
    func isStreaming(sessionId: String) -> Bool {
        return activeStreams[sessionId] != nil || acpBusy
    }
    
    // MARK: - opencode ACP 后端
    
    /// 通过 opencode ACP 协议发送问题（真正的流式输出）
    private func sendViaOpencode(
        noteContent: String,
        sessionId: String,
        model: String,
        onSessionReady: (@Sendable (String) -> Void)? = nil,
        onChunk: @escaping @Sendable (String) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        // 提取最后一个问题
        guard let question = extractLastQuestion(from: noteContent) else {
            onError("未找到有效的问题内容")
            return
        }
        
        acpBusy = true
        
        Task { @MainActor in
            do {
                // 确保 ACP 连接已建立
                try await ensureACPConnection(model: model, onChunk: onChunk)
                
                let effectiveSessionId = try await ensureConversationSession(
                    preferredSessionId: sessionId,
                    systemPrompt: FloatingButtonConfigManager.shared.config.aiSystemPrompt
                )
                if effectiveSessionId != sessionId {
                    onSessionReady?(effectiveSessionId)
                }
                
                // 存储 onComplete 回调，等 chunks 全部到达后在 handleParsedACPMessage 中调用
                acpOnComplete = onComplete
                
                // 发送 prompt 请求
                // 注意：prompt 响应（stopReason: end_turn）比 chunks 先返回
                // 所以不能在此处 onComplete，需要等 chunks 到达
                let _ = try await sendACPRequest(method: "session/prompt", params: [
                    "sessionId": effectiveSessionId,
                    "prompt": [
                        ["type": "text", "text": question]
                    ]
                ] as [String: Any])
                
                // prompt 响应已返回，chunks 会在之后短暂延迟到达
                // 设置一个延迟 timer 来调用 onComplete（每收到一个 chunk 就重置 timer）
                scheduleACPCompletion()
                
            } catch {
                acpBusy = false
                // 检测到进程退出/管道断开类错误，立即重启 ACP 并重试本次请求
                let errorMsg = "\(error)"
                let isConnectionError = errorMsg.contains("进程已退出") || errorMsg.contains("pipe") || errorMsg.contains("管道")
                if isConnectionError {
                    Logger.shared.log("🔌 ACP: 连接断开，立即重启并重试: \(errorMsg)")
                    // 通知用户正在重启
                    onChunk("\n\n> 🔄 ACP 服务已断开，正在自动重启...\n\n")
                    await self.disconnectACP()
                    self.shouldMaintainConnection = true
                    do {
                        // 立即重启 ACP
                        try await self.ensureACPConnection(model: model, onChunk: onChunk)
                        let newSessionId = try await self.ensureConversationSession(
                            preferredSessionId: sessionId,
                            systemPrompt: FloatingButtonConfigManager.shared.config.aiSystemPrompt
                        )
                        if newSessionId != sessionId {
                            onSessionReady?(newSessionId)
                        }
                        onChunk("> ✅ ACP 服务已重启，正在重新发送请求...\n\n")
                        self.acpOnComplete = onComplete
                        self.acpBusy = true
                        let _ = try await self.sendACPRequest(method: "session/prompt", params: [
                            "sessionId": newSessionId,
                            "prompt": [
                                ["type": "text", "text": question]
                            ]
                        ] as [String: Any])
                        self.scheduleACPCompletion()
                    } catch {
                        self.acpBusy = false
                        Logger.shared.log("❌ ACP: 重启后重试失败: \(error.localizedDescription)")
                        onError("opencode ACP 错误: \(error.localizedDescription)")
                    }
                } else if errorMsg.contains("超时") {
                    Logger.shared.log("🔌 ACP: 请求超时，触发重连: \(errorMsg)")
                    let wasMaintaining = self.shouldMaintainConnection
                    await self.disconnectACP()
                    if wasMaintaining {
                        self.shouldMaintainConnection = true
                        self.scheduleReconnectIfNeeded()
                    }
                    onError("opencode ACP 错误: \(error.localizedDescription)")
                } else {
                    onError("opencode ACP 错误: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 确保使用指定会话：优先 load，失败则创建新会话并返回有效会话ID
    private func ensureConversationSession(
        preferredSessionId: String,
        systemPrompt: String
    ) async throws -> String {
        let targetSessionId = preferredSessionId.trimmingCharacters(in: .whitespacesAndNewlines)

        if !targetSessionId.isEmpty {
            if acpSessionId == targetSessionId {
                return targetSessionId
            }

            do {
                Logger.shared.log("🔌 ACP: 尝试加载会话: \(targetSessionId)")
                let _ = try await sendACPRequest(method: "session/load", params: [
                    "sessionId": targetSessionId,
                    "cwd": NSTemporaryDirectory(),
                    "mcpServers": []
                ] as [String: Any])
                acpSessionId = targetSessionId
                acpLastActivityTime = Date()
                Logger.shared.log("✅ ACP: 会话加载成功: \(targetSessionId)")
                return targetSessionId
            } catch {
                Logger.shared.log("⚠️ ACP: 会话加载失败，改为创建新会话: \(error.localizedDescription)")
            }
        }

        return try await createACPNewSession(systemPrompt: systemPrompt)
    }

    /// 创建新的 ACP 会话并切换到 aix-chat 模式
    private func createACPNewSession(systemPrompt: String) async throws -> String {
        var sessionParams: [String: Any] = [
            "cwd": NSTemporaryDirectory(),
            "mcpServers": []
        ]
        if !systemPrompt.isEmpty {
            sessionParams["systemPrompt"] = systemPrompt
        }

        let sessionResult = try await sendACPRequest(method: "session/new", params: sessionParams)
        guard let sid = sessionResult["sessionId"] as? String else {
            throw NSError(domain: "AIService", code: -2, userInfo: [NSLocalizedDescriptionKey: "ACP 创建会话失败：未返回 sessionId"])
        }

        acpSessionId = sid
        acpStatus = .connected
        acpLastActivityTime = Date()
        Logger.shared.log("🔌 ACP: 已创建新会话: \(sid)")

        do {
            let _ = try await sendACPRequest(method: "session/set_mode", params: [
                "sessionId": sid,
                "modeId": "aix-chat"
            ])
            Logger.shared.log("🔌 ACP: 已切换到 aix-chat 模式")
        } catch {
            Logger.shared.log("🔌 ACP: 切换 aix-chat 模式失败（使用默认模式）: \(error.localizedDescription)")
        }

        return sid
    }
    
    /// 延迟调用 ACP 完成回调（每收到 chunk 就重置以等待更多 chunks）
    private func scheduleACPCompletion() {
        acpChunkTimer?.invalidate()
        acpChunkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finalizeACPCompletion()
            }
        }
    }
    
    /// 最终执行 ACP 完成
    private func finalizeACPCompletion() {
        acpChunkTimer?.invalidate()
        acpChunkTimer = nil
        acpBusy = false
        acpOnComplete?()
        acpOnComplete = nil
    }
    
    /// 确保 ACP 连接已建立，如果没有则创建（被动重连入口）
    private func ensureACPConnection(
        model: String,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws {
        // 通过发消息触发连接时，也标记为应保持连接
        shouldMaintainConnection = true
        
        // 检查现有连接是否健康
        if let process = acpProcess, acpSessionId != nil {
            if process.isRunning {
                // 进程健康时直接复用，避免空闲后主动断开带来的重连抖动
                acpOnChunk = onChunk
                return
            } else {
                Logger.shared.log("🔌 ACP: 进程已退出（isRunning=false），重建连接")
                await disconnectACP()
            }
        } else if acpProcess != nil {
            // 进程存在但会话丢失
            Logger.shared.log("🔌 ACP: 进程存在但会话丢失，清理重建")
            await disconnectACP()
        }
        
        acpStatus = .connecting
        Logger.shared.log("🔌 ACP: 开始连接...")
        
        // 确保 AIX 知识问答 agent 文件存在
        ensureAIXAgentFile()
        
        // 查找 opencode
        let opencodePath = findOpencodePath()
        guard !opencodePath.isEmpty else {
            acpStatus = .disconnected
            throw NSError(domain: "AIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到 opencode 命令，请先安装 opencode CLI"])
        }
        Logger.shared.log("🔌 ACP: 找到 opencode: \(opencodePath)")
        
        // 创建 Process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: opencodePath)
        process.arguments = ["acp", "--cwd", NSTemporaryDirectory()]
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // 异步读取 stderr 用于调试
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    Logger.shared.log("🔌 ACP stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
        
        try process.run()
        acpProcess = process
        acpStdinPipe = stdinPipe
        acpStdoutPipe = stdoutPipe
        acpOnChunk = onChunk

        let connectionToken = UUID()
        acpConnectionToken = connectionToken
        Logger.shared.log("🔌 ACP: opencode acp 进程已启动 (PID: \(process.processIdentifier))")
        
        // 启动后台读取任务（持续读取 stdout 的 JSON-RPC 消息）
        startReadLoop(stdoutPipe: stdoutPipe, connectionToken: connectionToken)
        
        // 发送 initialize 请求
        Logger.shared.log("🔌 ACP: 发送 initialize 请求...")
        let initResult = try await sendACPRequest(method: "initialize", params: [
            "protocolVersion": 1,
            "clientCapabilities": [
                "fs": ["readTextFile": false, "writeTextFile": false],
                "terminal": false
            ],
            "clientInfo": ["name": "AIX", "version": AppVersion.display]
        ] as [String: Any])
        Logger.shared.log("🔌 ACP: initialize 响应: \(initResult)")
        
        // 初始化完成后先创建默认会话，后续发送消息时会按笔记会话进行 load/new
        Logger.shared.log("🔌 ACP: 创建默认会话...")
        let systemPrompt = FloatingButtonConfigManager.shared.config.aiSystemPrompt
        let sid = try await createACPNewSession(systemPrompt: systemPrompt)
        Logger.shared.log("🔌 ACP: 连接完成，会话 ID: \(sid)")

        // 连接成功，重置重连计数并启动健康检查
        acpReconnectCount = 0
        startACPHealthCheck()
    }
    
    /// 启动后台读取循环，持续从 stdout 读取 JSON-RPC 消息
    private func startReadLoop(stdoutPipe: Pipe, connectionToken: UUID) {
        let handle = stdoutPipe.fileHandleForReading
        let lineReader = ACPLineReader()
        
        // 预先创建 @Sendable 回调来避免捕获 self
        let onExit: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.handleACPProcessExit(connectionToken: connectionToken) }
        }
        let onMessage: @Sendable (ParsedACPMessage) -> Void = { [weak self] parsed in
            Task { @MainActor in self?.handleParsedACPMessage(parsed) }
        }
        
        handle.readabilityHandler = { fileHandle in
            let chunk = fileHandle.availableData
            if chunk.isEmpty {
                fileHandle.readabilityHandler = nil
                onExit()
                return
            }
            
            let parsedMessages = lineReader.feed(chunk)
            for parsed in parsedMessages {
                onMessage(parsed)
            }
        }
    }
    
    /// 线程安全的行缓冲解析器
    private final class ACPLineReader: @unchecked Sendable {
        private var buffer = Data()
        private let lock = NSLock()
        
        func feed(_ chunk: Data) -> [ParsedACPMessage] {
            lock.lock()
            defer { lock.unlock() }
            
            buffer.append(chunk)
            var results: [ParsedACPMessage] = []
            
            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                
                guard !lineData.isEmpty else { continue }
                results.append(AIService.parseACPLine(lineData))
            }
            
            return results
        }
    }
    
    /// 解析后的 ACP 消息（所有字段都是 Sendable）
    private enum ParsedACPMessage: Sendable {
        case response(id: Int, result: Data)   // result 的原始 JSON Data
        case error(id: Int, code: Int, message: String)
        case sessionUpdate(type: String, text: String?)
        case unknown
    }
    
    /// 在非隔离上下文中解析 JSON-RPC 消息为 Sendable 类型
    private nonisolated static func parseACPLine(_ lineData: Data) -> ParsedACPMessage {
        guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return .unknown
        }
        
        // 响应消息
        if let id = json["id"] as? Int {
            if let result = json["result"] as? [String: Any],
               let resultData = try? JSONSerialization.data(withJSONObject: result) {
                return .response(id: id, result: resultData)
            }
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "未知错误"
                let code = error["code"] as? Int ?? -1
                return .error(id: id, code: code, message: message)
            }
        }
        
        // session/update 通知 — 实际格式: params.update.sessionUpdate + params.update.content
        if let method = json["method"] as? String, method == "session/update",
           let params = json["params"] as? [String: Any],
           let update = params["update"] as? [String: Any],
           let sessionUpdate = update["sessionUpdate"] as? String {
            var text: String? = nil
            if sessionUpdate == "agent_message_chunk",
               let content = update["content"] as? [String: Any],
               let contentType = content["type"] as? String,
               contentType == "text" {
                text = content["text"] as? String
            }
            return .sessionUpdate(type: sessionUpdate, text: text)
        }
        
        return .unknown
    }
    
    /// 处理已解析的 ACP 消息（MainActor 上下文）
    private func handleParsedACPMessage(_ message: ParsedACPMessage) {
        switch message {
        case .response(let id, let resultData):
            if let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
                acpPendingRequests[id]?.resume(returning: result)
            } else {
                acpPendingRequests[id]?.resume(returning: [:])
            }
            acpPendingRequests.removeValue(forKey: id)
            acpLastActivityTime = Date()
            
        case .error(let id, let code, let message):
            acpPendingRequests[id]?.resume(throwing: NSError(domain: "ACP", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
            acpPendingRequests.removeValue(forKey: id)
            
        case .sessionUpdate(_, let text):
            if let text = text {
                acpOnChunk?(text)
                acpLastActivityTime = Date()
                // 收到新 chunk，重置完成计时器
                if acpOnComplete != nil {
                    scheduleACPCompletion()
                }
            }
            
        case .unknown:
            break
        }
    }
    
    /// 处理 ACP 进程退出
    private func handleACPProcessExit(connectionToken: UUID? = nil) {
        if let token = connectionToken, token != acpConnectionToken {
            Logger.shared.log("🔌 ACP: 忽略旧连接退出回调")
            return
        }
        Logger.shared.log("🔌 ACP: 进程已退出")
        acpStatus = .disconnected
        acpSessionId = nil
        // 取消所有等待中的请求
        for (_, continuation) in acpPendingRequests {
            continuation.resume(throwing: NSError(domain: "ACP", code: -3, userInfo: [NSLocalizedDescriptionKey: "ACP 进程已退出"]))
        }
        acpPendingRequests.removeAll()
        
        // 自动重连
        scheduleReconnectIfNeeded()
    }
    
    /// 发送 JSON-RPC 请求并等待响应（带超时）
    private func sendACPRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        acpRequestId += 1
        let requestId = acpRequestId
        
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": method,
            "params": params
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NSError(domain: "ACP", code: -4, userInfo: [NSLocalizedDescriptionKey: "JSON 序列化失败"])
        }
        
        let line = jsonString + "\n"
        
        // session/prompt 给 120 秒，其他 30 秒
        let timeoutSeconds = method == "session/prompt" ? 120 : 30
        
        return try await withCheckedThrowingContinuation { continuation in
            acpPendingRequests[requestId] = continuation
            
            guard let pipe = acpStdinPipe else {
                acpPendingRequests.removeValue(forKey: requestId)
                continuation.resume(throwing: NSError(domain: "ACP", code: -5, userInfo: [NSLocalizedDescriptionKey: "ACP stdin pipe 不可用"]))
                return
            }
            
            // 安全写入管道（捕获异常）
            if let data = line.data(using: .utf8) {
                do {
                    try pipe.fileHandleForWriting.write(contentsOf: data)
                    Logger.shared.log("🔌 ACP: 已发送请求 #\(requestId) [\(method)]")
                } catch {
                    acpPendingRequests.removeValue(forKey: requestId)
                    continuation.resume(throwing: NSError(domain: "ACP", code: -7, userInfo: [NSLocalizedDescriptionKey: "管道写入失败: \(error.localizedDescription)"]))
                    return
                }
            } else {
                acpPendingRequests.removeValue(forKey: requestId)
                continuation.resume(throwing: NSError(domain: "ACP", code: -6, userInfo: [NSLocalizedDescriptionKey: "数据编码失败"]))
                return
            }
            
            // 超时定时器
            Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutSeconds), repeats: false) { [weak self] _ in
                Task { @MainActor in
                    if let cont = self?.acpPendingRequests.removeValue(forKey: requestId) {
                        Logger.shared.log("🔌 ACP: 请求 #\(requestId) [\(method)] 超时(\(timeoutSeconds)秒)")
                        cont.resume(throwing: NSError(domain: "ACP", code: -8, userInfo: [NSLocalizedDescriptionKey: "ACP 请求超时(\(timeoutSeconds)秒): \(method)"]))
                    }
                }
            }
        }
    }
    
    /// 手动启动 ACP 服务（公开方法，用于设置页面和自动启动）
    func connectACP() async {
        guard acpStatus == .disconnected else { return }
        shouldMaintainConnection = true
        acpReconnectCount = 0
        let model = FloatingButtonConfigManager.shared.config.opencodeModel
        do {
            try await ensureACPConnection(model: model, onChunk: { _ in })
            Logger.shared.log("✅ ACP 服务已启动")
            startACPHealthCheck()
        } catch {
            Logger.shared.log("❌ ACP 服务启动失败: \(error.localizedDescription)")
            acpStatus = .disconnected
            scheduleReconnectIfNeeded()
        }
    }
    
    /// 确保 AIX 知识问答 agent 文件存在
    private nonisolated func ensureAIXAgentFile() {
        let fm = FileManager.default
        let agentDir = NSString("~/.config/opencode/agents").expandingTildeInPath
        let agentFile = (agentDir as NSString).appendingPathComponent("aix-chat.md")
        
        if fm.fileExists(atPath: agentFile) { return }
        
        // 创建目录
        try? fm.createDirectory(atPath: agentDir, withIntermediateDirectories: true)
        
        // 写入 agent 文件
        let content = """
        ---
        description: AIX 知识问答助手，只做纯文本聊天，不使用任何工具
        mode: primary
        tools:
          write: false
          edit: false
          bash: false
          glob: false
          grep: false
          read: false
          fetch: false
          webfetch: false
          todoadd: false
          todoremove: false
          todocomplete: false
          task: false
        permission:
          edit: deny
          bash: deny
          webfetch: deny
        ---
        
        你是一个知识问答助手。请用简洁清晰的中文回答用户的问题。
        
        规则：
        - 只做纯文本对话，不要调用任何工具
        - 不要读取、修改、创建任何文件
        - 不要执行任何命令
        - 专注于回答用户的知识性问题
        """.split(separator: "\n").map { line in
            // 去掉每行前面的8个空格缩进
            let s = String(line)
            if s.hasPrefix("        ") { return String(s.dropFirst(8)) }
            return s
        }.joined(separator: "\n")
        
        try? content.write(toFile: agentFile, atomically: true, encoding: .utf8)
    }
    
    /// 断开 ACP 连接
    func disconnectACP() async {
        shouldMaintainConnection = false
        acpReconnectCount = 0
        stopACPHealthCheck()

        // 先切换连接代次，避免旧进程退出回调误伤新连接
        acpConnectionToken = UUID()
        
        acpReadTask?.cancel()
        acpReadTask = nil
        acpSessionId = nil
        acpOnChunk = nil
        acpStatus = .disconnected

        acpStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        
        // 取消所有等待中的请求
        for (_, continuation) in acpPendingRequests {
            continuation.resume(throwing: NSError(domain: "ACP", code: -3, userInfo: [NSLocalizedDescriptionKey: "连接已断开"]))
        }
        acpPendingRequests.removeAll()
        
        if let process = acpProcess, process.isRunning {
            process.terminate()
        }
        acpProcess = nil
        acpStdinPipe = nil
        acpStdoutPipe = nil
    }
    
    // MARK: - ACP 连接保活
    
    /// 调度自动重连（指数退避）
    private func scheduleReconnectIfNeeded() {
        guard shouldMaintainConnection, !acpReconnecting else { return }
        guard acpReconnectCount < AIService.acpMaxReconnect else {
            Logger.shared.log("🔌 ACP: 重连次数已达上限(\(AIService.acpMaxReconnect))，停止重连")
            return
        }
        
        acpReconnectCount += 1
        // 指数退避：3s, 6s, 12s, 24s, 48s
        let delay = 3.0 * pow(2.0, Double(acpReconnectCount - 1))
        Logger.shared.log("🔌 ACP: 将在 \(Int(delay)) 秒后尝试第 \(acpReconnectCount) 次重连")
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self = self, self.shouldMaintainConnection, self.acpStatus == .disconnected else { return }
            self.acpReconnecting = true
            let model = FloatingButtonConfigManager.shared.config.opencodeModel
            do {
                try await self.ensureACPConnection(model: model, onChunk: { _ in })
                Logger.shared.log("✅ ACP: 第 \(self.acpReconnectCount) 次重连成功")
                self.acpReconnectCount = 0
                self.startACPHealthCheck()
            } catch {
                Logger.shared.log("❌ ACP: 第 \(self.acpReconnectCount) 次重连失败: \(error.localizedDescription)")
                self.acpStatus = .disconnected
                self.scheduleReconnectIfNeeded()
            }
            self.acpReconnecting = false
        }
    }
    
    /// 启动 ACP 健康检查定时器（每30秒检测一次）
    private func startACPHealthCheck() {
        stopACPHealthCheck()
        acpHealthTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkACPHealth()
            }
        }
    }
    
    /// 停止 ACP 健康检查定时器
    private func stopACPHealthCheck() {
        acpHealthTimer?.invalidate()
        acpHealthTimer = nil
    }
    
    /// 检查 ACP 连接健康状态
    private func checkACPHealth() {
        guard shouldMaintainConnection else { return }
        
        if acpStatus == .disconnected && !acpReconnecting {
            Logger.shared.log("🔌 ACP: 健康检查发现连接断开，触发重连")
            scheduleReconnectIfNeeded()
            return
        }
        
        // 进程存在但已退出
        if let process = acpProcess, !process.isRunning {
            Logger.shared.log("🔌 ACP: 健康检查发现进程已退出")
            handleACPProcessExit()
        }
    }
    
    /// 查找 opencode 可执行文件路径
    private nonisolated func findOpencodePath() -> String {
        let knownPaths = [
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            "/usr/bin/opencode"
        ]
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // 尝试通过 which 查找
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["opencode"]
        let whichPipe = Pipe()
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = FileHandle.nullDevice
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        } catch {}
        return ""
    }
}

/// URLSession delegate 用于处理 SSE 流式数据
private class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let onChunk: (String) -> Void
    let onComplete: () -> Void
    let onError: (String) -> Void
    private var buffer = ""
    
    init(onChunk: @escaping (String) -> Void, onComplete: @escaping () -> Void, onError: @escaping (String) -> Void) {
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            onError("API 返回错误: HTTP \(httpResponse.statusCode)")
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text
        
        // 按行处理 SSE 数据
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
            buffer = String(buffer[newlineRange.upperBound...])
            
            processSSELine(line)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 处理buffer中剩余数据
        if !buffer.isEmpty {
            processSSELine(buffer)
            buffer = ""
        }
        
        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled {
                // 用户取消，不报错
                onComplete()
            } else {
                onError("网络错误: \(error.localizedDescription)")
            }
        } else {
            onComplete()
        }
    }
    
    private func processSSELine(_ line: String) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmedLine.hasPrefix("data: ") else { return }
        
        let jsonStr = String(trimmedLine.dropFirst(6))
        
        if jsonStr == "[DONE]" {
            onComplete()
            return
        }
        
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return
        }
        
        if !content.isEmpty {
            onChunk(content)
        }
    }
}
