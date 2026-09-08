import Foundation
import AppKit
import Combine

@MainActor
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var history: [ClipboardItem] = []
    private var lastChangeCount: Int = 0
    private var timer: AnyCancellable?
    private let saveKey = "clipboard_history"
    
    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        loadHistory()
        
        // 启动监听（不在初始化时强制添加当前剪切板内容），等待后续变更触发
        startMonitoring()
        
        // 监听配置变化以同步历史记录上限
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChanged),
            name: Notification.Name("floatingButtonConfigChanged"),
            object: nil
        )
    }
    
    @objc private func handleConfigChanged() {
        let limit = FloatingButtonConfigManager.shared.config.clipboardHistoryLimit
        if history.count > limit {
            history = Array(history.prefix(limit))
            saveHistory()
        }
    }
    
    let clipboardHistoryFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AIX") // Ensure you use your app's Bundle Identifier or Name
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("clipboard_history.json")
    }()
    
    // Serial queue for file operations to avoid conflict
    private let saveQueue = DispatchQueue(label: "com.aix.clipboard.save", qos: .background)
    
    private func loadHistory() {
        // 异步加载历史记录，不阻塞应用启动
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            
            var loaded: [ClipboardItem] = []
            var needsMigration = false
            
            // 1. 尝试从文件加载
            if let data = try? Data(contentsOf: self.clipboardHistoryFileURL),
               let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
                loaded = decoded
                // 检查是否需要迁移（旧格式：JSON 文件 > 1MB 说明含有内联图片数据）
                if data.count > 1_000_000 {
                    needsMigration = true
                }
            }
            // 2. 回退：从 UserDefaults 迁移
            else if let data = UserDefaults.standard.data(forKey: self.saveKey),
                    let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
                loaded = decoded
                needsMigration = true
                UserDefaults.standard.removeObject(forKey: self.saveKey)
            }
            
            // 过滤掉缓存文件丢失的非文本项
            loaded = loaded.filter { item in
                if item.type == .text || item.type == .file { return true }
                return !item.data.isEmpty
            }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let limit = FloatingButtonConfigManager.shared.config.clipboardHistoryLimit
                if loaded.count > limit {
                    loaded = Array(loaded.prefix(limit))
                }
                self.history = loaded
                
                // 旧格式数据迁移：重新保存为新格式（图片存缓存文件）
                if needsMigration {
                    self.saveHistory()
                }
            }
        }
    }
    
    private func saveHistory() {
        let currentHistory = self.history
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(currentHistory)
                try data.write(to: self.clipboardHistoryFileURL, options: .atomic)
            } catch {
                print("Failed to save clipboard history: \(error)")
            }
        }
    }
    
    func startMonitoring() {
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkClipboard()
            }
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        if let item = fetchCurrentItem() {
            addToHistory(item)
        }
    }
    
    private func fetchCurrentItem() -> ClipboardItem? {
        let pasteboard = NSPasteboard.general
        
        // 优先处理文本
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let data = text.data(using: .utf8) {
                return ClipboardItem(id: UUID(), timestamp: Date(), type: .text, data: data)
            }
        }
        
        // 处理图片
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            return ClipboardItem(id: UUID(), timestamp: Date(), type: .image, data: imageData)
        }
        
        // 处理文件路径
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            let paths = fileURLs.map { $0.path }.joined(separator: "\n")
            if let data = paths.data(using: .utf8) {
                return ClipboardItem(id: UUID(), timestamp: Date(), type: .file, data: data)
            }
        }
        
        return nil
    }
    
    private func addToHistory(_ item: ClipboardItem) {
        // 去重：查找历史中是否有相同内容，若有则移除旧记录
        var newHistory = history
        var removedItems: [ClipboardItem] = []
        
        // 文本用内容比较去重，非文本用数据大小+类型快速比较
        newHistory.removeAll {
            let isDuplicate: Bool
            if $0.type == item.type {
                if item.type == .text {
                    isDuplicate = $0.data == item.data
                } else {
                    // 非文本数据用大小比较（避免大数据逐字节比较）
                    isDuplicate = $0.data.count == item.data.count && $0.data == item.data
                }
            } else {
                isDuplicate = false
            }
            if isDuplicate { removedItems.append($0) }
            return isDuplicate
        }
        
        // 插入新记录到顶部
        newHistory.insert(item, at: 0)
        
        let limit = FloatingButtonConfigManager.shared.config.clipboardHistoryLimit
        if newHistory.count > limit {
            let overflow = Array(newHistory[limit...])
            removedItems.append(contentsOf: overflow)
            newHistory = Array(newHistory.prefix(limit))
        }
        
        // 如果内容和顺序完全相同则跳过保存
        guard newHistory.count != history.count || newHistory.first?.id != history.first?.id else {
            return
        }
        
        history = newHistory
        saveHistory()
        
        // 清理被移除项的缓存文件
        if !removedItems.isEmpty {
            let itemsToClean = removedItems
            saveQueue.async {
                for removed in itemsToClean {
                    removed.removeCacheFile()
                }
            }
        }
        
        // 播放配置的提示音
        let config = FloatingButtonConfigManager.shared.config
        if config.enableClipboardSound {
            if let sound = NSSound(named: config.clipboardSound) {
                sound.play()
            } else {
                NSSound.beep()
            }
        }
    }
    
    func copyToClipboard(_ item: ClipboardItem, shouldAddToHistory: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text, .file:
            if let text = item.stringValue {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            pasteboard.setData(item.data, forType: .tiff)
        case .other:
            break
        }
        
        // 更新 changeCount 避免再次触发监听
        lastChangeCount = pasteboard.changeCount
        
        // 历史记录管理异步执行，不阻塞复制操作
        if shouldAddToHistory {
            let itemCopy = item
            Task { @MainActor [weak self] in
                self?.addToHistory(itemCopy)
            }
        }
    }
    
    /// 将指定项移到历史记录顶部（不触发提示音）
    func moveToTop(_ item: ClipboardItem) {
        var newHistory = history
        var removedItems: [ClipboardItem] = []
        newHistory.removeAll {
            let isDuplicate = $0.type == item.type && $0.data == item.data
            if isDuplicate { removedItems.append($0) }
            return isDuplicate
        }
        // 创建新的 item（保留类型和数据，更新时间戳）
        let updatedItem = ClipboardItem(id: UUID(), timestamp: Date(), type: item.type, data: item.data)
        newHistory.insert(updatedItem, at: 0)
        
        let limit = FloatingButtonConfigManager.shared.config.clipboardHistoryLimit
        if newHistory.count > limit {
            let overflow = Array(newHistory[limit...])
            removedItems.append(contentsOf: overflow)
            newHistory = Array(newHistory.prefix(limit))
        }
        
        history = newHistory
        saveHistory()
        
        // 清理旧缓存文件
        if !removedItems.isEmpty {
            let itemsToClean = removedItems
            saveQueue.async {
                for removed in itemsToClean {
                    removed.removeCacheFile()
                }
            }
        }
    }
}
