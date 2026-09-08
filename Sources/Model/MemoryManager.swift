import Foundation
import AppKit

struct MemoryEntry: Identifiable, Codable {
    let id: UUID
    let noteId: UUID
    var palaceCue: String
    var keywords: [String]
    var lastReviewedAt: Date?
    var nextReviewAt: Date
    var intervalLevel: Int
    var masteryLevel: Int
}

@MainActor
final class MemoryManager: ObservableObject {

    static let shared = MemoryManager()

    @Published private(set) var entries: [MemoryEntry] = []

    @Published var fixedReviewTimes: [String] = ["21:00"] {
        didSet { saveFixedReviewTimes() }
    }

    @Published var palaceLayoutContext: String = "" {
        didSet { savePalaceLayout() }
    }

    private let entriesKey = "memoryEntries"
    private let fixedReviewTimesKey = "memoryFixedReviewTimes"
    private let palaceLayoutContextKey = "memoryPalaceLayoutContext"
    private let lastTriggeredSlotKey = "memoryLastTriggeredSlot"
    private let store: SettingsStore
    private var reminderTimer: Timer?

    private init() {
        self.store = AppDatabase.shared.settingsStore
        // 加载固定复习时间点数组
        if let timesStr = store.loadConfig(key: fixedReviewTimesKey),
           let data = timesStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.fixedReviewTimes = decoded
        }
        // 加载房间布局
        self.palaceLayoutContext = store.loadConfig(key: palaceLayoutContextKey) ?? ""
        loadEntries()
        startReminderTimer()
    }

    // MARK: - 固定复习时间管理
    func addFixedReviewTime(_ time: String) {
        guard !fixedReviewTimes.contains(time) else { return }
        fixedReviewTimes.append(time)
        fixedReviewTimes.sort()
    }

    func removeFixedReviewTime(at index: Int) {
        guard index >= 0 && index < fixedReviewTimes.count else { return }
        fixedReviewTimes.remove(at: index)
    }

    func markKnowledgeAsMemory(note: Note) {
        guard note.isKnowledge else { return }

        if let index = entries.firstIndex(where: { $0.noteId == note.id }) {
            entries[index].palaceCue = buildPalaceCue(from: note.content)
            entries[index].keywords = extractKeywords(from: note.content)
            saveEntries()

            Task { @MainActor in
                let cue = await AIService.shared.generateMemoryPalaceCue(content: note.content, roomLayoutContext: self.palaceLayoutContext)
                if let updateIndex = self.entries.firstIndex(where: { $0.noteId == note.id }) {
                    self.entries[updateIndex].palaceCue = cue
                    self.saveEntries()
                }
            }
            return
        }

        let entry = MemoryEntry(
            id: UUID(),
            noteId: note.id,
            palaceCue: buildPalaceCue(from: note.content),
            keywords: extractKeywords(from: note.content),
            lastReviewedAt: nil,
            nextReviewAt: Date().addingTimeInterval(6 * 3600),
            intervalLevel: 0,
            masteryLevel: 0
        )
        entries.append(entry)
        saveEntries()

        Task { @MainActor in
            let cue = await AIService.shared.generateMemoryPalaceCue(content: note.content, roomLayoutContext: self.palaceLayoutContext)
            if let updateIndex = self.entries.firstIndex(where: { $0.noteId == note.id }) {
                self.entries[updateIndex].palaceCue = cue
                self.saveEntries()
            }
        }
    }

    func unmarkKnowledgeMemory(noteId: UUID) {
        entries.removeAll { $0.noteId == noteId }
        saveEntries()
    }

    func regeneratePalaceCue(for entryId: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let noteId = entries[index].noteId
        guard let note = NoteManager.shared.notes.first(where: { $0.id == noteId }) else { return }

        Task { @MainActor in
            let cue = await AIService.shared.generateMemoryPalaceCue(
                content: note.content,
                roomLayoutContext: self.palaceLayoutContext
            )
            if let updateIndex = self.entries.firstIndex(where: { $0.id == entryId }) {
                self.entries[updateIndex].palaceCue = cue
                self.saveEntries()
            }
        }
    }

    func dueEntriesSorted(by taskNotes: [Note]) -> [MemoryEntry] {
        let now = Date()
        let due = entries.filter { $0.nextReviewAt <= now }
        guard !taskNotes.isEmpty else {
            return due.sorted { $0.nextReviewAt < $1.nextReviewAt }
        }

        let taskKeywords = Set(taskNotes.flatMap { extractKeywords(from: $0.content) })
        return due.sorted { lhs, rhs in
            let lScore = relevanceScore(entry: lhs, taskKeywords: taskKeywords)
            let rScore = relevanceScore(entry: rhs, taskKeywords: taskKeywords)
            if lScore == rScore {
                return lhs.nextReviewAt < rhs.nextReviewAt
            }
            return lScore > rScore
        }
    }

    func dueEntriesSortedSmart(by taskNotes: [Note]) async -> [MemoryEntry] {
        let base = dueEntriesSorted(by: taskNotes)
        guard !taskNotes.isEmpty else { return base }

        let context = taskNotes.map { $0.content }.joined(separator: "\n")
        if context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return base
        }

        let top = Array(base.prefix(8))
        if top.isEmpty { return base }

        var semanticScores: [UUID: Int] = [:]
        for entry in top {
            let knowledge = NoteManager.shared.notes.first(where: { $0.id == entry.noteId })?.content ?? ""
            let score = await AIService.shared.scoreTaskRelevance(taskContext: context, knowledgeContent: knowledge)
            semanticScores[entry.id] = score
        }

        let rerankedTop = top.sorted { lhs, rhs in
            let lScore = semanticScores[lhs.id] ?? 0
            let rScore = semanticScores[rhs.id] ?? 0
            if lScore == rScore {
                return lhs.nextReviewAt < rhs.nextReviewAt
            }
            return lScore > rScore
        }

        let topIds = Set(rerankedTop.map { $0.id })
        let tail = base.filter { !topIds.contains($0.id) }
        return rerankedTop + tail
    }

    /// 标记为已掌握，直接跳到最大间隔（60 天后复习）
    func markAsMastered(entryId: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[idx].masteryLevel = 2
        entries[idx].lastReviewedAt = Date()
        entries[idx].intervalLevel = 5
        entries[idx].nextReviewAt = Date().addingTimeInterval(60 * 24 * 3600)
        saveEntries()
    }

    func scheduleAfterReview(entryId: UUID, quality: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }

        let boundedQuality = max(0, min(2, quality))
        entries[idx].masteryLevel = boundedQuality
        entries[idx].lastReviewedAt = Date()

        if boundedQuality == 0 {
            entries[idx].intervalLevel = 0
            entries[idx].nextReviewAt = Date().addingTimeInterval(12 * 3600)
        } else if boundedQuality == 1 {
            entries[idx].intervalLevel = min(entries[idx].intervalLevel + 1, 2)
            let intervals: [TimeInterval] = [24 * 3600, 3 * 24 * 3600, 7 * 24 * 3600]
            entries[idx].nextReviewAt = Date().addingTimeInterval(intervals[entries[idx].intervalLevel])
        } else {
            entries[idx].intervalLevel = min(entries[idx].intervalLevel + 1, 4)
            let intervals: [TimeInterval] = [24 * 3600, 3 * 24 * 3600, 7 * 24 * 3600, 15 * 24 * 3600, 30 * 24 * 3600]
            entries[idx].nextReviewAt = Date().addingTimeInterval(intervals[entries[idx].intervalLevel])
        }

        saveEntries()
    }

    func nonIntrusivePrompt(for inProgressNotes: [Note]) {
        Task { @MainActor in
            let candidates = await dueEntriesSortedSmart(by: inProgressNotes)
            guard let first = candidates.first else { return }

            NotificationCenter.default.post(
                name: Notification.Name("MemoryContextPrompt"),
                object: nil,
                userInfo: [
                    "entryId": first.id.uuidString,
                    "noteId": first.noteId.uuidString,
                    "message": "相关知识接近复习窗口，建议立即回顾"
                ]
            )
        }
    }

    private func startReminderTimer() {
        stopReminderTimer()
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickReminder()
            }
        }
    }

    private func stopReminderTimer() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }

    private func tickReminder() {
        guard let matchedTime = matchedFixedReviewTime() else { return }
        guard canTriggerSlot(matchedTime) else { return }

        Task { @MainActor in
            // 收集最近完成的任务（最近17天内）
            let recentCompleted = NoteManager.shared.notes.filter { note in
                note.isCompleted && !note.isDeleted &&
                note.createdAt.timeIntervalSinceNow > -7 * 24 * 3600
            }

            // 收集艰宾浩斯曲线到期的条目（到下一个固定时间点之前的）
            let nextSlotDeadline = self.nextFixedTimeSlotDeadline()
            let curveEntries = self.entries.filter { $0.nextReviewAt <= nextSlotDeadline }

            // 合并排序：优先任务关联度，再按曲线紧迫度
            let candidates: [MemoryEntry]
            if !recentCompleted.isEmpty {
                candidates = await dueEntriesSortedSmart(by: recentCompleted)
            } else if !curveEntries.isEmpty {
                candidates = curveEntries.sorted { $0.nextReviewAt < $1.nextReviewAt }
            } else {
                return
            }

            guard let first = candidates.first else { return }

            NotificationCenter.default.post(
                name: Notification.Name("MemoryReviewReminder"),
                object: nil,
                userInfo: [
                    "entryId": first.id.uuidString,
                    "noteId": first.noteId.uuidString,
                    "message": "有记忆条目到达复习时间"
                ]
            )

            self.markSlotTriggered(matchedTime)
        }
    }

    /// 检查当前时间是否匹配任一固定复习时间点（±15分钟）
    private func matchedFixedReviewTime() -> String? {
        let now = Date()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        guard let nowHour = comps.hour, let nowMinute = comps.minute else { return nil }
        let nowTotal = nowHour * 60 + nowMinute

        for time in fixedReviewTimes {
            let parts = time.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]) else { continue }
            let fixedTotal = hour * 60 + minute
            if abs(nowTotal - fixedTotal) <= 15 {
                return time
            }
        }
        return nil
    }

    /// 检查某时间点今天是否已触发
    private func canTriggerSlot(_ time: String) -> Bool {
        let key = lastTriggeredSlotKey + "_" + time
        let today = dayString(Date())
        let last = store.loadConfig(key: key) ?? ""
        return today != last
    }

    /// 标记某时间点今天已触发
    private func markSlotTriggered(_ time: String) {
        let key = lastTriggeredSlotKey + "_" + time
        try? store.saveConfig(key: key, value: dayString(Date()))
    }

    /// 计算下一个固定时间点的截止时间（用于判断哪些曲线条目应纳入本次复习）
    private func nextFixedTimeSlotDeadline() -> Date {
        let now = Date()
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        guard let nowHour = comps.hour, let nowMinute = comps.minute else { return now }
        let nowTotal = nowHour * 60 + nowMinute

        var closestFuture: Int?
        for time in fixedReviewTimes {
            let parts = time.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]) else { continue }
            let total = hour * 60 + minute
            if total > nowTotal + 15 {
                if closestFuture == nil || total < closestFuture! {
                    closestFuture = total
                }
            }
        }

        if let next = closestFuture {
            // 今天内的下一个时间点
            var dateComps = calendar.dateComponents([.year, .month, .day], from: now)
            dateComps.hour = next / 60
            dateComps.minute = next % 60
            return calendar.date(from: dateComps) ?? now.addingTimeInterval(12 * 3600)
        } else {
            // 没有更晚的时间点，取明天第一个
            return now.addingTimeInterval(24 * 3600)
        }
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func buildPalaceCue(from content: String) -> String {
        let seed = shortText(content)
        return "在熟悉的房间入口放置‘\(seed)’的夸张图像，沿主通道依次关联关键概念。"
    }

    private func extractKeywords(from content: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let words = content
            .lowercased()
            .components(separatedBy: separators)
            .filter { $0.count >= 2 }
        return Array(Set(words)).prefix(20).map { $0 }
    }

    private func shortText(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "核心概念" }
        let line = trimmed.components(separatedBy: "\n").first ?? trimmed
        return String(line.prefix(18))
    }

    private func relevanceScore(entry: MemoryEntry, taskKeywords: Set<String>) -> Int {
        let overlap = Set(entry.keywords).intersection(taskKeywords).count
        let nearCurveBonus = entry.nextReviewAt.timeIntervalSinceNow < 6 * 3600 ? 2 : 0
        return overlap * 3 + nearCurveBonus
    }

    private func saveFixedReviewTimes() {
        guard let data = try? JSONEncoder().encode(fixedReviewTimes),
              let str = String(data: data, encoding: .utf8) else { return }
        try? store.saveConfig(key: fixedReviewTimesKey, value: str)
    }

    private func savePalaceLayout() {
        try? store.saveConfig(key: palaceLayoutContextKey, value: palaceLayoutContext)
    }

    private func loadEntries() {
        guard let str = store.loadConfig(key: entriesKey),
              let data = str.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MemoryEntry].self, from: data) else {
            self.entries = []
            return
        }
        self.entries = decoded
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries),
              let str = String(data: data, encoding: .utf8) else { return }
        try? store.saveConfig(key: entriesKey, value: str)
    }
}
