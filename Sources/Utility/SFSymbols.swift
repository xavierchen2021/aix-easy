
import Foundation

struct SFSymbolCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String // SF Symbol for the category itself
    let symbols: [String]
}

struct SFSymbols {
    static let allCategories: [SFSymbolCategory] = [
        SFSymbolCategory(name: "常用", icon: "star", symbols: [
            "star", "star.fill", "heart", "heart.fill", "circle", "circle.fill", 
            "square", "square.fill", "checkmark", "checkmark.circle", "checkmark.circle.fill",
            "xmark", "xmark.circle", "xmark.circle.fill", "plus", "plus.circle", "plus.circle.fill",
            "minus", "minus.circle", "minus.circle.fill", "exclamationmark.circle", "info.circle",
            "questionmark.circle", "gear", "gearshape", "gearshape.fill"
        ]),
        
        SFSymbolCategory(name: "通讯", icon: "message", symbols: [
            "message", "message.fill", "bubble.left", "bubble.right", "envelope", "envelope.fill",
            "phone", "phone.fill", "phone.circle", "video", "video.fill", "mic", "mic.fill",
            "person", "person.fill", "person.2", "person.3", "person.circle", "person.crop.circle"
        ]),
        
        SFSymbolCategory(name: "对象 & 工具", icon: "hammer", symbols: [
            "folder", "folder.fill", "paperplane", "paperplane.fill", "archivebox", "trash", 
            "trash.fill", "doc", "doc.text", "doc.fill", "terminal", "terminal.fill",
            "calculator", "hammer", "wrench", "screwdriver", "scissors", "magnifyingglass",
            "house", "house.fill", "lock", "lock.open", "key", "cart", "cart.fill", "bag",
            "creditcard", "gift", "eyeglasses", "book", "bookmark", "flag", "flag.fill",
            "bell", "bell.fill", "tag", "flashlight.on.fill", "camera", "printer"
        ]),
        
        SFSymbolCategory(name: "媒体", icon: "play.circle", symbols: [
            "play", "play.fill", "pause", "pause.fill", "stop", "stop.fill", 
            "forward", "backward", "shuffle", "repeat", "music.note", "music.quarternote.3",
            "speaker", "speaker.wave.2", "speaker.slash", "headphones", "airpods"
        ]),
        
        SFSymbolCategory(name: "设备", icon: "desktopcomputer", symbols: [
            "desktopcomputer", "laptopcomputer", "macpro.gen3", "display", "iphone", 
            "ipad", "ipod", "applewatch", "keyboard", "mouse", "printer.fill",
            "server.rack", "externaldrive", "internaldrive", "wifi", "dot.radiowaves.left.and.right"
        ]),
        
        SFSymbolCategory(name: "天气", icon: "cloud.sun", symbols: [
            "sun.max", "sun.max.fill", "moon", "moon.fill", "cloud", "cloud.fill",
            "cloud.rain", "cloud.snow", "cloud.bolt", "wind", "snowflake", "thermometer",
            "umbrella"
        ]),
        
        SFSymbolCategory(name: "编辑", icon: "pencil", symbols: [
            "pencil", "pencil.circle", "eraser", "square.and.pencil", "highlighter", 
            "scissors", "paperclip", "link", "text.alignleft", "text.aligncenter", 
            "text.alignright", "bold", "italic", "underline"
        ]),
        
        SFSymbolCategory(name: "Arrows", icon: "arrow.right", symbols: [
            "arrow.up", "arrow.down", "arrow.left", "arrow.right",
            "arrow.up.circle", "arrow.down.circle", "arrow.left.circle", "arrow.right.circle",
            "chevron.up", "chevron.down", "chevron.left", "chevron.right",
            "arrow.uturn.left", "arrow.uturn.right", "arrow.clockwise", "arrow.counterclockwise"
        ])
    ]
    
    static var allSymbols: [String] {
        allCategories.flatMap { $0.symbols }
    }
}
