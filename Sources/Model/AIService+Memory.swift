import Foundation

struct MemorySemanticEvaluation {
    let quality: Int
    let feedback: String
}

extension AIService {
    func generateMemoryPalaceCue(content: String, roomLayoutContext: String? = nil) async -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "在熟悉空间里放置一个可视化核心概念符号，并串联成路径。"
        }

        let layout = roomLayoutContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prompt: String
        if layout.isEmpty {
            prompt = "请把以下知识内容转成1条记忆宫殿联想线索，要求：图像化、夸张、可定位（地点+角色+动作），不超过80字。内容：\n\(trimmed)"
        } else {
            prompt = "用户提供了自己的房间布局，请基于该布局生成1条记忆宫殿线索，要求：优先使用用户房间中的具体位置作为锚点，线索图像化、夸张、可行动，不超过100字。\n房间布局：\n\(layout)\n\n知识内容：\n\(trimmed)"
        }
        if let response = try? await requestSingleResponse(userPrompt: prompt) {
            return response
        }

        return "在熟悉房间入口放置“\(String(trimmed.prefix(16)))”的夸张图像，并沿路径串联关键动作。"
    }

    func generateMemoryQuestion(noteContent: String, taskContext: String) async -> String {
        let prompt = "你是记忆教练。基于知识内容和任务上下文，生成1个开放式语义复习问题，要求考察理解与迁移，不要直接复述原文，不超过120字。\n知识内容：\n\(noteContent)\n\n任务上下文：\n\(taskContext)"
        if let response = try? await requestSingleResponse(userPrompt: prompt) {
            return response
        }
        return "请用自己的话说明这条知识的核心含义，并举一个与当前任务相关的应用例子。"
    }

    func evaluateMemoryAnswer(noteContent: String, question: String, answer: String, taskContext: String) async -> MemorySemanticEvaluation {
        let fallback = heuristicEvaluate(noteContent: noteContent, answer: answer)

        let judgePrompt = "你是记忆评估器。请基于知识内容、问题、用户回答进行语义评估，输出严格JSON：{\"quality\":0|1|2,\"feedback\":\"简短中文反馈\"}。quality含义：0=忘记，1=模糊，2=清晰。\n知识内容：\n\(noteContent)\n\n问题：\n\(question)\n\n用户回答：\n\(answer)\n\n任务上下文：\n\(taskContext)"

        guard let response = try? await requestSingleResponse(userPrompt: judgePrompt),
              let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quality = json["quality"] as? Int,
              let feedback = json["feedback"] as? String else {
            return fallback
        }

        return MemorySemanticEvaluation(
            quality: max(0, min(2, quality)),
            feedback: feedback
        )
    }

    func scoreTaskRelevance(taskContext: String, knowledgeContent: String) async -> Int {
        let trimmedTask = taskContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKnowledge = knowledgeContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTask.isEmpty || trimmedKnowledge.isEmpty {
            return 0
        }

        let prompt = "请评估任务上下文与知识内容的语义相关度，只输出0到100的整数，不要输出其他文本。\n任务：\n\(trimmedTask)\n\n知识：\n\(trimmedKnowledge)"

        if let response = try? await requestSingleResponse(userPrompt: prompt),
           let score = Int(response.filter { $0.isNumber }) {
            return max(0, min(100, score))
        }

        let taskTokens = Set(tokenize(trimmedTask))
        let knowledgeTokens = Set(tokenize(trimmedKnowledge))
        if taskTokens.isEmpty || knowledgeTokens.isEmpty { return 0 }
        let overlap = taskTokens.intersection(knowledgeTokens).count
        let ratio = Double(overlap) / Double(max(taskTokens.count, 1))
        return Int(max(0, min(100, ratio * 100)))
    }

    private func requestSingleResponse(userPrompt: String) async throws -> String {
        let config = FloatingButtonConfigManager.shared.config
        guard !config.aiApiKey.isEmpty, !config.aiUrl.isEmpty else {
            throw NSError(domain: "AIServiceMemory", code: -1)
        }

        var urlString = config.aiUrl
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "chat/completions"

        guard let url = URL(string: urlString) else {
            throw NSError(domain: "AIServiceMemory", code: -2)
        }

        let messages: [[String: String]] = [
            ["role": "system", "content": "你是严谨的中文记忆教练，只输出用户要求内容，不添加无关文本。"],
            ["role": "user", "content": userPrompt]
        ]

        let body: [String: Any] = [
            "model": config.aiModel,
            "messages": messages,
            "stream": false,
            "temperature": 0.3
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.aiApiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "AIServiceMemory", code: -3)
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func heuristicEvaluate(noteContent: String, answer: String) -> MemorySemanticEvaluation {
        let noteWords = Set(tokenize(noteContent))
        let answerWords = Set(tokenize(answer))
        guard !noteWords.isEmpty else {
            return MemorySemanticEvaluation(quality: 0, feedback: "回答信息不足，建议先回顾后再作答。")
        }

        let overlap = noteWords.intersection(answerWords).count
        let ratio = Double(overlap) / Double(noteWords.count)

        if ratio >= 0.35 {
            return MemorySemanticEvaluation(quality: 2, feedback: "理解较清晰，可拉长下次复习间隔。")
        } else if ratio >= 0.15 {
            return MemorySemanticEvaluation(quality: 1, feedback: "已有基础记忆，建议短周期再巩固。")
        }
        return MemorySemanticEvaluation(quality: 0, feedback: "关键点回忆不足，建议尽快再次复习。")
    }

    private func tokenize(_ text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return text.lowercased().components(separatedBy: separators).filter { $0.count >= 2 }
    }
}
