import Foundation
import AppKit

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let timestamp: Date
    let type: ClipboardType
    let data: Data
    
    enum ClipboardType: String, Codable {
        case text
        case image
        case file
        case other
    }
    
    // MARK: - 缓存目录（非文本数据以文件引用方式存储）
    
    static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("AIX/clipboard_cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }()
    
    // MARK: - Custom Codable（非文本数据存为缓存文件，JSON 中只存文件名引用）
    
    enum CodingKeys: String, CodingKey {
        case id, timestamp, type, data, cacheFile
    }
    
    init(id: UUID, timestamp: Date, type: ClipboardType, data: Data) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.data = data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        type = try container.decode(ClipboardType.self, forKey: .type)
        
        if let cacheFile = try container.decodeIfPresent(String.self, forKey: .cacheFile) {
            // 非文本数据：从缓存文件加载
            let cacheURL = ClipboardItem.cacheDirectory.appendingPathComponent(cacheFile)
            data = (try? Data(contentsOf: cacheURL)) ?? Data()
        } else {
            // 文本数据：内联存储（兼容旧格式）
            data = try container.decode(Data.self, forKey: .data)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(type, forKey: .type)
        
        if type == .text || type == .file {
            // 文本和文件路径：内联存储（数据量小）
            try container.encode(data, forKey: .data)
        } else {
            // 图片等非文本：保存到缓存文件，JSON 中只存文件名
            let fileName = id.uuidString
            let cacheURL = ClipboardItem.cacheDirectory.appendingPathComponent(fileName)
            try? data.write(to: cacheURL)
            try container.encode(fileName, forKey: .cacheFile)
        }
    }
    
    /// 删除此项的缓存文件
    func removeCacheFile() {
        guard type != .text && type != .file else { return }
        let cacheURL = ClipboardItem.cacheDirectory.appendingPathComponent(id.uuidString)
        try? FileManager.default.removeItem(at: cacheURL)
    }
    
    // MARK: - 属性访问
    
    var stringValue: String? {
        guard type == .text else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    var imageValue: NSImage? {
        guard type == .image else { return nil }
        return NSImage(data: data)
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.id == rhs.id
    }
}
