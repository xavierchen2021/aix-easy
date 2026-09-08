import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 常用文件/文件夹管理器
@MainActor
class FavoriteManager: ObservableObject {
    static let shared = FavoriteManager()
    
    @Published var items: [FavoriteItem] = []
    
    private init() {
        loadItems()
    }
    
    func loadItems() {
        do {
            items = try AppDatabase.shared.favoriteStore.fetchAll()
        } catch {
            print("❌ 加载常用文件失败: \(error)")
        }
    }
    
    func addItem(url: URL) {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let item = FavoriteItem(name: url.lastPathComponent, path: url.path, isDirectory: isDir)
        
        // 检查是否已存在相同路径
        guard !items.contains(where: { $0.path == item.path }) else { return }
        
        do {
            try AppDatabase.shared.favoriteStore.insert(item)
            items.insert(item, at: 0)
            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
        } catch {
            print("❌ 添加常用文件失败: \(error)")
        }
    }
    
    func deleteItem(id: UUID) {
        do {
            try AppDatabase.shared.favoriteStore.delete(id: id)
            items.removeAll { $0.id == id }
            NotificationCenter.default.post(name: Notification.Name("NoteViewModeChanged"), object: nil)
        } catch {
            print("❌ 删除常用文件失败: \(error)")
        }
    }
    
    func openItem(_ item: FavoriteItem) {
        let url = URL(fileURLWithPath: item.path)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 常用文件列表视图

struct FavoriteListContentView: View {
    @StateObject private var favoriteManager = FavoriteManager.shared
    @State private var isDragOver = false
    @State private var pulseOpacity: Double = 0.3
    @State private var emptyPulse: Bool = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if favoriteManager.items.isEmpty {
                    emptyStateView
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(favoriteManager.items) { item in
                                FavoriteItemView(item: item)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.leading, 16)
                        .padding(.trailing, 80)
                        .padding(.bottom, 16)
                    }
                }
            }
            
            // 拖拽提示覆盖层
            if isDragOver {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(pulseOpacity))
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 36, weight: .light))
                                .foregroundColor(.white)
                            Text(L10n.tr("favorites.releaseToAdd"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    )
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulseOpacity = 0.5
                        }
                    }
                    .onDisappear {
                        pulseOpacity = 0.3
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDragOver)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundColor(.gray)
                .symbolEffect(.pulse, options: .repeating)
            Text(L10n.tr("favorites.dragHere"))
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(emptyPulse ? 0.9 : 0.7))
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: emptyPulse)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.blue.opacity(emptyPulse ? 0.6 : 0.2), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: emptyPulse)
        )
        .padding(.horizontal, 16)
        .onAppear {
            emptyPulse = true
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else { return }
                Task { @MainActor in
                    FavoriteManager.shared.addItem(url: url)
                }
            }
        }
    }
}

struct FavoriteItemView: View {
    let item: FavoriteItem
    @StateObject private var favoriteManager = FavoriteManager.shared
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.iconName)
                .font(.system(size: 16))
                .foregroundColor(item.isDirectory ? Color(red: 0.3, green: 0.6, blue: 0.95) : .gray)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .lineLimit(1)
                
                Text(item.path)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if isHovered {
                Button(action: {
                    favoriteManager.deleteItem(id: item.id)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            favoriteManager.openItem(item)
        }
        .contextMenu {
            Button {
                let url = URL(fileURLWithPath: item.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label(L10n.tr("favorites.showInFinder"), systemImage: "folder")
            }
            
            Divider()
            
            Button(role: .destructive) {
                favoriteManager.deleteItem(id: item.id)
            } label: {
                Label(L10n.tr("common.delete"), systemImage: "trash")
            }
        }
    }
}
