import Foundation

/// 休息提醒日志管理器
/// 记录提醒系统的关键事件到文件，自动管理日志大小和清理
final class ReminderLogger: @unchecked Sendable {
    
    static let shared = ReminderLogger()
    
    private let logDirectory: URL
    private var currentLogFile: URL
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.aix.reminder.logger")
    
    /// 单个日志文件最大大小（2MB）
    private let maxLogFileSize: UInt64 = 2 * 1024 * 1024
    /// 保留日志天数
    private let logRetentionDays: Int = 7
    /// 上次检查文件大小的时间
    private var lastSizeCheckTime: Date = .distantPast
    /// 文件大小检查间隔（60秒）
    private let sizeCheckInterval: TimeInterval = 60
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        let logPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)[0]
        logDirectory = URL(fileURLWithPath: logPath).appendingPathComponent("Logs").appendingPathComponent("AIX")
        
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let dateString = df.string(from: Date())
        currentLogFile = logDirectory.appendingPathComponent("reminder_\(dateString).log")
        
        // 启动时清理过期日志
        cleanupOldLogs()
        
        logInfo("🚀 日志系统已初始化，日志位置: \(currentLogFile.path)")
    }
    
    func logInfo(_ message: String) {
        writeLog(level: "INFO", message: message)
    }
    
    func logEvent(_ message: String) {
        writeLog(level: "EVENT", message: message)
    }
    
    func logAction(_ message: String) {
        writeLog(level: "ACTION", message: message)
    }
    
    func logError(_ message: String) {
        writeLog(level: "ERROR", message: message)
    }
    
    private func writeLog(level: String, message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 检查日期是否变更，自动切换日志文件
            self.rotateLogFileIfNeeded()
            
            // 定期检查文件大小（避免每次写入都检查）
            let now = Date()
            if now.timeIntervalSince(self.lastSizeCheckTime) > self.sizeCheckInterval {
                self.lastSizeCheckTime = now
                self.truncateIfOversized()
            }
            
            let timestamp = self.dateFormatter.string(from: Date())
            let logEntry = "[\(timestamp)] [\(level)] \(message)\n"
            
            guard let data = logEntry.data(using: .utf8) else { return }
            
            if FileManager.default.fileExists(atPath: self.currentLogFile.path) {
                if let fileHandle = FileHandle(forWritingAtPath: self.currentLogFile.path) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: self.currentLogFile)
            }
        }
    }
    
    /// 日期变更时切换到新的日志文件
    private func rotateLogFileIfNeeded() {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let dateString = df.string(from: Date())
        let expectedFile = logDirectory.appendingPathComponent("reminder_\(dateString).log")
        
        if expectedFile != currentLogFile {
            currentLogFile = expectedFile
        }
    }
    
    /// 文件超出大小限制时，保留后半部分内容
    private func truncateIfOversized() {
        guard FileManager.default.fileExists(atPath: currentLogFile.path) else { return }
        
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: currentLogFile.path)
            guard let fileSize = attrs[.size] as? UInt64, fileSize > maxLogFileSize else { return }
            
            // 读取文件内容，保留后半部分
            let data = try Data(contentsOf: currentLogFile)
            let keepFrom = data.count / 2
            let truncatedData = data.suffix(from: keepFrom)
            
            // 找到第一个换行符，确保从完整行开始
            if let newlineIndex = truncatedData.firstIndex(of: UInt8(ascii: "\n")) {
                let cleanData = truncatedData.suffix(from: truncatedData.index(after: newlineIndex))
                let header = "[日志截断] 文件超过\(maxLogFileSize / 1024 / 1024)MB，已自动清理旧日志\n".data(using: .utf8) ?? Data()
                try (header + cleanData).write(to: currentLogFile)
            }
        } catch {
            // 截断失败不影响正常运行
        }
    }
    
    /// 清理过期日志文件
    private func cleanupOldLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: self.logDirectory, includingPropertiesForKeys: [.creationDateKey]) else { return }
            
            let calendar = Calendar.current
            let cutoffDate = calendar.date(byAdding: .day, value: -self.logRetentionDays, to: Date()) ?? Date()
            
            for file in files {
                guard file.pathExtension == "log",
                      file.lastPathComponent.hasPrefix("reminder_") else { continue }
                
                // 从文件名中提取日期 reminder_YYYYMMDD.log
                let name = file.deletingPathExtension().lastPathComponent
                let dateStr = String(name.dropFirst("reminder_".count))
                
                let df = DateFormatter()
                df.dateFormat = "yyyyMMdd"
                
                if let fileDate = df.date(from: dateStr), fileDate < cutoffDate {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }
}
