import SwiftUI
import AppKit

struct ColorListView: View {
    @StateObject private var noteManager = NoteManager.shared
    @State private var hoveredNoteId: UUID? = nil
    @State private var showCopyMenuId: UUID? = nil
    
    var colorNotes: [Note] {
        noteManager.notes.filter { $0.groupId == NoteGroup.colorGroupId && !$0.isDeleted }
            .sorted(by: { $0.createdAt > $1.createdAt })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                Text(L10n.tr("colors.history"))
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Button(action: {
                    ColorPickerManager.shared.startPicking()
                }) {
                    Image(systemName: "eyedropper")
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("colors.colorPicker"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.3))
            
            if colorNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.3))
                    Text(L10n.tr("colors.noRecords"))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(colorNotes) { note in
                            ColorItemRow(note: note, isHovered: hoveredNoteId == note.id)
                                .onHover { hovering in
                                    hoveredNoteId = hovering ? note.id : nil
                                }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.15).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ColorItemRow: View {
    let note: Note
    let isHovered: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 颜色预览块
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: note.colorHex))
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(note.content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                
                Text(formatDate(note.createdAt))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            if isHovered {
                Menu {
                    Button(L10n.tr("colors.copyHex")) {
                        copyToClipboard(note.content)
                    }
                    Button(L10n.tr("colors.copyRGB")) {
                        if let color = NSColor(hex: note.content) {
                            let r = Int(color.redComponent * 255)
                            let g = Int(color.greenComponent * 255)
                            let b = Int(color.blueComponent * 255)
                            copyToClipboard("\(r), \(g), \(b)")
                        }
                    }
                    Button(L10n.tr("colors.copySwiftUI")) {
                        if let color = NSColor(hex: note.content) {
                            let r = String(format: "%.3f", color.redComponent)
                            let g = String(format: "%.3f", color.greenComponent)
                            let b = String(format: "%.3f", color.blueComponent)
                            copyToClipboard("Color(red: \(r), green: \(g), blue: \(b))")
                        }
                    }
                    Button(L10n.tr("colors.copyAppKit")) {
                        if let color = NSColor(hex: note.content) {
                            let r = String(format: "%.3f", color.redComponent)
                            let g = String(format: "%.3f", color.greenComponent)
                            let b = String(format: "%.3f", color.blueComponent)
                            copyToClipboard("NSColor(red: \(r), green: \(g), blue: \(b), alpha: 1.0)")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        NoteManager.shared.deleteNote(id: note.id)
                    } label: {
                        Label(L10n.tr("common.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.white.opacity(0.6))
                        .padding(4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden) // 隐藏下拉箭头
                .frame(width: 24)
            }
        }
        .padding(8)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            // 默认复制 Hex
            copyToClipboard(note.content)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 如果需要显示 Toast，可以通过 NotificationCenter 发送
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
