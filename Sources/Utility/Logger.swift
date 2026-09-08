import Foundation

@MainActor
class Logger {
    static let shared = Logger()
    
    private let logFilePath: String
    private let fileHandle: FileHandle?
    
    private init() {
        // 创建日志文件路径
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let logDirectory = (documentsPath as NSString).appendingPathComponent("AIX_Logs")
        
        // 确保日志目录存在
        try? FileManager.default.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)
        
        // 创建日志文件（使用日期时间命名）
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "aix_\(timestamp).log"
        
        logFilePath = (logDirectory as NSString).appendingPathComponent(fileName)
        
        // 创建文件
        FileManager.default.createFile(atPath: logFilePath, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: logFilePath)
        
        // 写入开始标记
        log("========================================")
        log("AIX 日志开始")
        log("时间: \(Date())")
        log("========================================")
    }
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"
        
        // 同时输出到控制台
        print(logMessage, terminator: "")
        
        // 写入文件
        if let data = logMessage.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
    
    deinit {
        fileHandle?.closeFile()
    }
}
