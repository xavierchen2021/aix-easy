import Foundation
import CryptoKit

/// Edge TTS 音频缓存管理器
/// 缓存目录：~/Library/Application Support/AIX/tts_cache/
/// 音频文件：{sha256}.mp3
/// 索引文件：index.json
@MainActor
class TTSCacheManager: ObservableObject {
    static let shared = TTSCacheManager()
    
    @Published var entries: [CacheEntry] = []
    @Published var totalSize: Int64 = 0
    
    // MARK: - 缓存条目模型
    
    struct CacheEntry: Identifiable, Codable {
        let hash: String        // SHA256 哈希（不含扩展名）
        let textPreview: String // 文本前 80 字摘要
        let voice: String       // 语音名称
        let fileSize: Int64     // 字节数
        let createdAt: Date     // 创建时间
        
        var id: String { hash }
        
        var fileSizeDisplay: String {
            let kb = Double(fileSize) / 1024.0
            if kb < 1024 {
                return String(format: "%.1f KB", kb)
            }
            return String(format: "%.1f MB", kb / 1024.0)
        }
    }
    
    // MARK: - 缓存目录
    
    static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AIX/tts_cache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private static var indexURL: URL {
        cacheDirectory.appendingPathComponent("index.json")
    }
    
    private init() {
        loadIndex()
    }
    
    // MARK: - 缓存哈希
    
    /// 根据文本和语音生成唯一缓存 key
    static func cacheKey(text: String, voice: String) -> String {
        let input = "\(text)|\(voice)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - 查找缓存
    
    /// 查找缓存的音频数据，命中返回 Data，未命中返回 nil
    func lookup(text: String, voice: String) -> Data? {
        let hash = Self.cacheKey(text: text, voice: voice)
        let fileURL = Self.cacheDirectory.appendingPathComponent("\(hash).mp3")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        return try? Data(contentsOf: fileURL)
    }
    
    // MARK: - 存入缓存
    
    /// 将音频数据存入缓存
    func store(text: String, voice: String, audioData: Data) {
        let hash = Self.cacheKey(text: text, voice: voice)
        let fileURL = Self.cacheDirectory.appendingPathComponent("\(hash).mp3")
        
        // 写入音频文件
        do {
            try audioData.write(to: fileURL)
        } catch {
            print("[TTSCache] 写入缓存文件失败: \(error.localizedDescription)")
            return
        }
        
        // 更新索引
        let preview = String(text.prefix(80))
        let entry = CacheEntry(
            hash: hash,
            textPreview: preview,
            voice: voice,
            fileSize: Int64(audioData.count),
            createdAt: Date()
        )
        
        // 去重（如果已存在相同 hash 则替换）
        entries.removeAll { $0.hash == hash }
        entries.insert(entry, at: 0)
        totalSize = entries.reduce(0) { $0 + $1.fileSize }
        saveIndex()
    }
    
    // MARK: - 删除单条缓存
    
    func removeEntry(_ entry: CacheEntry) {
        let fileURL = Self.cacheDirectory.appendingPathComponent("\(entry.hash).mp3")
        try? FileManager.default.removeItem(at: fileURL)
        
        entries.removeAll { $0.hash == entry.hash }
        totalSize = entries.reduce(0) { $0 + $1.fileSize }
        saveIndex()
    }
    
    // MARK: - 清空所有缓存
    
    func clearAll() {
        for entry in entries {
            let fileURL = Self.cacheDirectory.appendingPathComponent("\(entry.hash).mp3")
            try? FileManager.default.removeItem(at: fileURL)
        }
        entries.removeAll()
        totalSize = 0
        saveIndex()
    }
    
    // MARK: - 索引持久化
    
    private func loadIndex() {
        guard FileManager.default.fileExists(atPath: Self.indexURL.path),
              let data = try? Data(contentsOf: Self.indexURL) else {
            entries = []
            totalSize = 0
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let decoded = try? decoder.decode([CacheEntry].self, from: data) else {
            entries = []
            totalSize = 0
            return
        }
        
        // 过滤掉音频文件已不存在的条目
        entries = decoded.filter { entry in
            let fileURL = Self.cacheDirectory.appendingPathComponent("\(entry.hash).mp3")
            return FileManager.default.fileExists(atPath: fileURL.path)
        }
        totalSize = entries.reduce(0) { $0 + $1.fileSize }
        
        // 如果有条目被过滤掉了，更新索引
        if entries.count != decoded.count {
            saveIndex()
        }
    }
    
    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: Self.indexURL)
    }
}
