import SwiftUI
import AppKit
import AVFoundation

/// TTS 缓存管理窗口
struct TTSCacheManagerView: View {
    @ObservedObject private var cacheManager = TTSCacheManager.shared
    @State private var showClearConfirm = false
    @State private var selectedEntries: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部统计栏
            HStack {
                Text("TTS 语音缓存")
                    .font(.headline)
                Spacer()
                Text("\(cacheManager.entries.count) 条 · \(formattedTotalSize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider()
            
            // 缓存列表
            if cacheManager.entries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("暂无缓存")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(cacheManager.entries) { entry in
                        TTSCacheEntryRow(entry: entry, onDelete: {
                            cacheManager.removeEntry(entry)
                        }, onPlay: {
                            playEntry(entry)
                        })
                    }
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            // 底部操作栏
            HStack {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清空所有", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(cacheManager.entries.isEmpty)
                
                Spacer()
                
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.open(TTSCacheManager.cacheDirectory)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 520, height: 400)
        .alert("确认清空", isPresented: $showClearConfirm) {
            Button("清空", role: .destructive) {
                cacheManager.clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有 TTS 语音缓存文件（\(formattedTotalSize)），此操作不可撤销。")
        }
    }
    
    private var formattedTotalSize: String {
        let kb = Double(cacheManager.totalSize) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        return String(format: "%.1f MB", kb / 1024.0)
    }
    
    private func playEntry(_ entry: TTSCacheManager.CacheEntry) {
        let fileURL = TTSCacheManager.cacheDirectory.appendingPathComponent("\(entry.hash).mp3")
        guard let data = try? Data(contentsOf: fileURL) else { return }
        TTSService.shared.playRawAudio(data, id: "cache_\(entry.hash)")
    }
}

/// 单条缓存条目行
struct TTSCacheEntryRow: View {
    let entry: TTSCacheManager.CacheEntry
    let onDelete: () -> Void
    let onPlay: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // 文本摘要
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.textPreview)
                    .font(.system(size: 12))
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    // 语音名称
                    Text(shortVoiceName(entry.voice))
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(3)
                    
                    // 文件大小
                    Text(entry.fileSizeDisplay)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // 创建时间
                    Text(formatDate(entry.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 试听按钮
            Button(action: onPlay) {
                Image(systemName: "play.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("试听")
            
            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.vertical, 2)
    }
    
    /// 从完整语音名提取简短名称：en-US-JennyNeural → Jenny
    private func shortVoiceName(_ voice: String) -> String {
        let parts = voice.split(separator: "-")
        if parts.count >= 3 {
            let name = String(parts[2])
            return name.replacingOccurrences(of: "Neural", with: "")
        }
        return voice
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 窗口管理

@MainActor
func openTTSCacheManagerWindow() {
    // 检查是否已有窗口
    for window in NSApplication.shared.windows {
        if window.title == "TTS 缓存管理" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
    
    let contentView = TTSCacheManagerView()
    let hostingController = NSHostingController(rootView: contentView)
    
    let window = NSWindow(contentViewController: hostingController)
    window.title = "TTS 缓存管理"
    window.styleMask = [.titled, .closable, .resizable]
    window.setContentSize(NSSize(width: 520, height: 400))
    window.minSize = NSSize(width: 420, height: 300)
    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
}
