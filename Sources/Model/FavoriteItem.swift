import Foundation

/// 常用文件/文件夹项目
struct FavoriteItem: Identifiable, Codable {
    let id: UUID
    let name: String      // 文件/文件夹名称
    let path: String      // 完整路径
    let isDirectory: Bool  // 是否为文件夹
    let createdAt: Date    // 添加时间
    
    init(id: UUID = UUID(), name: String, path: String, isDirectory: Bool, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.createdAt = createdAt
    }
    
    /// 文件图标名称（SF Symbol）
    var iconName: String {
        if isDirectory {
            return "folder.fill"
        }
        
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "ppt", "pptx": return "rectangle.split.3x1"
        case "txt", "md": return "doc.plaintext"
        case "swift", "py", "js", "ts", "java", "c", "cpp", "h", "m", "rs", "go": return "chevron.left.forwardslash.chevron.right"
        case "html", "css": return "globe"
        case "json", "yaml", "yml", "xml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic": return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "aac", "flac": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "dmg", "iso": return "opticaldisc"
        case "app": return "app"
        case "sh", "zsh", "bash": return "terminal"
        default: return "doc"
        }
    }
}
