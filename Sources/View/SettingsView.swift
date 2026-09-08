import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @ObservedObject private var reminderManager = ReminderManager.shared
    @State private var selectedTab = 0
    
    private var tabs: [(title: String, icon: String)] {
        [
            (L10n.tr("settings.general"), "gear"),
            (L10n.tr("settings.reminders"), "bell.fill"),
            (L10n.tr("settings.about"), "info.circle")
        ]
    }
    
    @State private var showAccessibilityAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标签栏
            HStack(spacing: 4) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    SettingsTabButton(
                        title: tabs[index].title,
                        icon: tabs[index].icon,
                        isSelected: selectedTab == index
                    ) {
                        selectedTab = index
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 64)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 主内容区域
            Group {
                switch selectedTab {
                case 0:
                    GeneralSettingsView()
                case 1:
                    ReminderSettingsView()
                case 2:
                    AboutSettingsView()
                default:
                    GeneralSettingsView()
                }
            }
            .frame(minWidth: 550, minHeight: 500)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 600)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 1 && !InputMonitor.hasAccessibilityPermission() {
                showAccessibilityAlert = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 用户聚焦窗口时检查权限，已授权则自动关闭弹窗
            if showAccessibilityAlert && InputMonitor.hasAccessibilityPermission() {
                showAccessibilityAlert = false
            }
        }
        .overlay {
            if showAccessibilityAlert {
                // 半透明遮罩
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                // 自定义权限弹窗
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    
                    Text(L10n.tr("permission.missing"))
                        .font(.system(size: 16, weight: .bold))
                    
                    Text(L10n.tr("permission.missingMsg"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    
                    HStack(spacing: 16) {
                        Button(L10n.tr("common.cancel")) {
                            showAccessibilityAlert = false
                            selectedTab = 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        
                        Button(L10n.tr("common.goToSettings")) {
                            InputMonitor.promptForAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
                )
                .frame(maxWidth: 380)
            }
        }
    }
    
}

struct SettingsTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - 通用设置
struct GeneralSettingsView: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @ObservedObject private var noteManager = NoteManager.shared
    @State private var selectedLanguage: AppLanguage = {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        return AppLanguage(rawValue: saved) ?? .system
    }()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 语言设置
                SettingsSection(title: L10n.tr("settings.language"), icon: "globe") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: L10n.tr("settings.language"),
                            description: L10n.tr("settings.languageDesc")
                        ) {
                            Picker("", selection: $selectedLanguage) {
                                ForEach(AppLanguage.allCases, id: \.self) { lang in
                                    Text(lang.displayName).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)
                            .onChange(of: selectedLanguage) { _, newValue in
                                UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
                                L10n.clearCache()
                            }
                        }
                    }
                }

                SettingsSection(title: "安全设置", icon: "lock.shield") {
                    GlobalPasswordSettingsView()
                }


                
                SettingsSection(title: L10n.tr("settings.windowSettings"), icon: "macwindow") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: L10n.tr("settings.noteMaxHeight"),
                            description: L10n.tr("settings.noteMaxHeightDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { Double(configManager.config.noteWindowHeight) },
                                        set: { configManager.updateNoteWindowHeight(CGFloat($0)) }
                                    ),
                                    in: 200...Double(NSScreen.main?.frame.height ?? 1000 - 200),
                                    step: 50
                                )
                                .frame(width: 200)
                                
                                Text("\(Int(configManager.config.noteWindowHeight))px")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 外观设置
                SettingsSection(title: L10n.tr("settings.appearance"), icon: "paintbrush") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: L10n.tr("settings.noteTheme"),
                            description: L10n.tr("settings.noteThemeDesc")
                        ) {
                            Picker("", selection: Binding(
                                get: { configManager.config.noteTheme },
                                set: { configManager.updateNoteTheme($0) }
                            )) {
                                ForEach(FloatingButtonConfig.NoteTheme.allCases, id: \.self) { theme in
                                    Text(theme.localizedName).tag(theme)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        
                        SettingsRow(
                            title: L10n.tr("settings.alwaysShowNoteActionButtons"),
                            description: L10n.tr("settings.alwaysShowNoteActionButtonsDesc")
                        ) {
                            Toggle("", isOn: Binding(
                                get: { configManager.config.alwaysShowNoteActionButtons },
                                set: { configManager.updateAlwaysShowNoteActionButtons($0) }
                            ))
                            .labelsHidden()
                        }
                    }
                }

                // 透明度设置
                SettingsSection(title: L10n.tr("settings.transparency"), icon: "square.dashed") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: L10n.tr("settings.noteTransparency"),
                            description: L10n.tr("settings.noteTransparencyDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { configManager.config.noteOpacity },
                                        set: { configManager.updateNoteOpacity($0) }
                                    ),
                                    in: 0.1...1.0,
                                    step: 0.05
                                )
                                .frame(width: 200)
                                
                                Text("\(Int(configManager.config.noteOpacity * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        SettingsRow(
                            title: L10n.tr("settings.toolbarTransparency"),
                            description: L10n.tr("settings.toolbarTransparencyDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { configManager.config.toolbarOpacity },
                                        set: { configManager.updateToolbarOpacity($0) }
                                    ),
                                    in: 0.1...1.0,
                                    step: 0.05
                                )
                                .frame(width: 200)
                                
                                Text("\(Int(configManager.config.toolbarOpacity * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        SettingsRow(
                            title: L10n.tr("settings.groupTransparency"),
                            description: L10n.tr("settings.groupTransparencyDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { configManager.config.groupOpacity },
                                        set: { configManager.updateGroupOpacity($0) }
                                    ),
                                    in: 0.1...1.0,
                                    step: 0.05
                                )
                                .frame(width: 200)
                                
                                Text("\(Int(configManager.config.groupOpacity * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 默认浏览器
                SettingsSection(title: L10n.tr("settings.defaultBrowser"), icon: "safari") {
                    SettingsRow(
                        title: L10n.tr("settings.systemDefaultBrowser"),
                        description: BrowserDetector.shared.isDefaultBrowser() ? L10n.tr("settings.isDefaultBrowser") : L10n.tr("settings.setDefaultBrowserDesc")
                    ) {
                        if BrowserDetector.shared.isDefaultBrowser() {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(L10n.tr("settings.alreadyDefault"))
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            }
                        } else {
                            Button(L10n.tr("common.goToSettings")) {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    BrowserListManagementView()
                    
                    SettingsRow(
                        title: L10n.tr("settings.autoCloseAfterSelect"),
                        description: L10n.tr("settings.autoCloseAfterSelectDesc")
                    ) {
                        HStack(spacing: 8) {
                            if configManager.config.browserAutoClose {
                                Picker("", selection: Binding(
                                    get: { configManager.config.browserAutoCloseDelay },
                                    set: { configManager.updateBrowserAutoCloseDelay($0) }
                                )) {
                                    Text(L10n.tr("settings.closeImmediately")).tag(0.0)
                                    Text(L10n.tr("settings.3sec")).tag(3.0)
                                    Text(L10n.tr("settings.5sec")).tag(5.0)
                                    Text(L10n.tr("settings.8sec")).tag(8.0)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                            }
                            
                            Toggle("", isOn: Binding(
                                get: { configManager.config.browserAutoClose },
                                set: { configManager.updateBrowserAutoClose($0) }
                            ))
                            .labelsHidden()
                        }
                    }
                }

                // 自动隐藏设置
                AutoHideSettingsSection()
                
                SettingsSection(title: L10n.tr("settings.clipboard"), icon: "doc.on.clipboard") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: L10n.tr("settings.historyLimit"),
                            description: L10n.tr("settings.historyLimitDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { Double(configManager.config.clipboardHistoryLimit) },
                                        set: { configManager.updateClipboardHistoryLimit(Int($0)) }
                                    ),
                                    in: 5...100,
                                    step: 5
                                )
                                .frame(width: 200)
                                
                                Text("\(configManager.config.clipboardHistoryLimit)条")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        SettingsRow(
                            title: L10n.tr("settings.copySound"),
                            description: L10n.tr("settings.copySoundDesc")
                        ) {
                            Toggle("", isOn: Binding(
                                get: { configManager.config.enableClipboardSound },
                                set: { configManager.updateEnableClipboardSound($0) }
                            ))
                            .labelsHidden()
                        }
                        
                        if configManager.config.enableClipboardSound {
                            SettingsRow(
                                title: L10n.tr("settings.soundSelection"),
                                description: L10n.tr("settings.soundSelectionDesc")
                            ) {
                                Picker("", selection: Binding(
                                    get: { configManager.config.clipboardSound },
                                    set: { configManager.updateClipboardSound($0) }
                                )) {
                                    ForEach(getSystemSounds(), id: \.self) { sound in
                                        Text(sound).tag(sound)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 180)
                            }
                        }
                    }
                }

                // 数据库路径设置
                SettingsSection(title: L10n.tr("settings.globalHotkeys"), icon: "keyboard") {
                    HotkeyConfigurationSection()
                }

                // 数据库路径设置
                SettingsSection(title: L10n.tr("settings.database"), icon: "server.rack") {
                    DatabaseSettingsView()
                }

                // 备份设置
                SettingsSection(title: L10n.tr("settings.dataBackup"), icon: "externaldrive.fill") {
                    BackupSettingsView()
                }
            }
            .padding(24)
        }
    }
}

// MARK: - 悬浮球设置
struct FloatingButtonSettingsView: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 显示模式 - 临时隐藏（分组显示模式已移至分组Tab）
                // SettingsSection(title: "显示模式", icon: "eye") {
                //     VStack(alignment: .leading, spacing: 16) {
                //         SettingsRow(
                //             title: "悬浮球显示模式",
                //             description: "选择悬浮球显示图标还是文字"
                //         ) { ... }
                //         SettingsRow(
                //             title: "分组显示模式",
                //             description: "设置分组内容的显示方式"
                //         ) { ... }
                //     }
                // }
                
                // 自定义图标 - 临时隐藏
                // SettingsSection(title: "自定义图标", icon: "star.circle") {
                //     VStack(alignment: .leading, spacing: 12) {
                //         Text("使用 SF Symbols 名称自定义悬浮球图标")
                //             .font(.caption)
                //             .foregroundColor(.secondary)
                //         
                //         ForEach(0..<configManager.config.buttonCount, id: \.self) { index in
                //             CustomIconRow(buttonIndex: index)
                //         }
                //     }
                // }
                
                // 呼吸效果 - 临时隐藏
                // SettingsSection(title: "呼吸效果", icon: "wind") {
                //     VStack(alignment: .leading, spacing: 16) {
                //         ...呼吸效果设置内容...
                //     }
                // }
            }
            .padding(24)
        }
    }
}

struct CustomIconRow: View {
    let buttonIndex: Int
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @State private var iconName: String = ""
    @State private var showPicker = false
    
    var body: some View {
        let action = configManager.config.buttonActions[buttonIndex] ?? .none
        let boundWindow = configManager.config.boundWindows[buttonIndex]
        
        let actionText: String = {
            var text = action.localizedName
            if action == .toggleWindow, let window = boundWindow {
                text += " (\(window.appName))"
            }
            return text
        }()
        
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("按钮 \(buttonIndex + 1)")
                    .font(.system(size: 14, weight: .medium))
                
                Text(actionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Picker Button
            Button(action: { showPicker = true }) {
                Image(systemName: iconName.isEmpty ? "square.dashed" : iconName)
                    .font(.system(size: 16))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(BorderedButtonStyle())
            .popover(isPresented: $showPicker) {
                SymbolPickerView(selectedSymbol: Binding(
                    get: { self.iconName },
                    set: { newVal in 
                        self.iconName = newVal
                        configManager.updateCustomIcon(index: buttonIndex, iconName: newVal)
                        // showPicker = false // Optional: close on select
                    }
                ))
            }
            
            TextField("图标名称", text: $iconName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 120)
                .onSubmit {
                    configManager.updateCustomIcon(index: buttonIndex, iconName: iconName)
                }
            
            if action == .toggleWindow && boundWindow != nil {
                Button(L10n.tr("settings.clearBinding")) {
                    configManager.unbindWindow(index: buttonIndex)
                }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            iconName = configManager.config.customIcons[buttonIndex] ?? ""
        }
    }
}

// MARK: - 分组设置
struct GroupSettingsView: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @ObservedObject private var noteManager = NoteManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 分组显示模式（从悬浮球Tab移入）
                SettingsSection(title: L10n.tr("settings.groupDisplayMode"), icon: "eye") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: L10n.tr("settings.groupDisplayMode"),
                            description: L10n.tr("settings.groupDisplayModeDesc")
                        ) {
                            Picker("", selection: Binding(
                                get: { configManager.config.groupDisplayMode },
                                set: { configManager.updateGroupDisplayMode($0) }
                            )) {
                                ForEach(FloatingButtonConfig.GroupDisplayMode.allCases, id: \.self) { mode in
                                    Text(mode.localizedName).tag(mode)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 180)
                        }
                    }
                }
                
                SettingsSection(title: L10n.tr("settings.defaultGroup"), icon: "folder") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: L10n.tr("settings.defaultNoteGroup"),
                            description: L10n.tr("settings.defaultNoteGroupDesc")
                        ) {
                            Picker("", selection: Binding(
                                get: { configManager.config.defaultNoteGroupId ?? NoteGroup.defaultId },
                                set: { configManager.updateDefaultNoteGroupId($0) }
                            )) {
                                ForEach(noteManager.getSortedGroups(isKnowledgeGroup: false)) { group in
                                    Text(group.name).tag(group.id)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 180)
                        }
                        
                        SettingsRow(
                            title: L10n.tr("settings.defaultKnowledgeGroup"),
                            description: L10n.tr("settings.defaultKnowledgeGroupDesc")
                        ) {
                            Picker("", selection: Binding(
                                get: { configManager.config.defaultKnowledgeGroupId ?? NoteGroup.defaultKnowledgeId },
                                set: { configManager.updateDefaultKnowledgeGroupId($0) }
                            )) {
                                ForEach(noteManager.getSortedGroups(isKnowledgeGroup: true)) { group in
                                    Text(group.name).tag(group.id)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 180)
                        }
                    }
                }
                
                // 笔记分组排序 - 临时隐藏
                // SettingsSection(title: "笔记分组排序", icon: "arrow.up.arrow.down") {
                //     VStack(alignment: .leading, spacing: 8) {
                //         Text("拖动分组以调整顺序")
                //             .font(.caption)
                //             .foregroundColor(.secondary)
                //             .padding(.bottom, 4)
                //         GroupSortList(isKnowledgeGroup: false)
                //     }
                // }
                
                // 知识分组排序 - 临时隐藏
                // SettingsSection(title: "知识分组排序", icon: "arrow.up.arrow.down") {
                //     VStack(alignment: .leading, spacing: 8) {
                //         Text("拖动分组以调整顺序")
                //             .font(.caption)
                //             .foregroundColor(.secondary)
                //             .padding(.bottom, 4)
                //         GroupSortList(isKnowledgeGroup: true)
                //     }
                // }
            }
            .padding(24)
        }
    }
}

// MARK: - 分组排序列表
struct GroupSortList: View {
    let isKnowledgeGroup: Bool
    @ObservedObject private var noteManager = NoteManager.shared
    @State private var draggingGroup: NoteGroup?
    
    var sortedGroups: [NoteGroup] {
        noteManager.getSortedGroups(isKnowledgeGroup: isKnowledgeGroup)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedGroups.enumerated()), id: \.element.id) { index, group in
                GroupSortRow(group: group, isDragging: draggingGroup?.id == group.id)
                    .padding(.vertical, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sortedGroups.map { $0.id })
                    .onDrag {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            self.draggingGroup = group
                        }
                        let provider = NSItemProvider(object: group.id.uuidString as NSString)
                        provider.suggestedName = group.name
                        return provider
                    }
                    .onDrop(of: [.text], delegate: GroupDropDelegate(
                        item: group,
                        items: sortedGroups,
                        draggingItem: $draggingGroup,
                        isKnowledgeGroup: isKnowledgeGroup
                    ))
                
                if group.id != sortedGroups.last?.id {
                    Divider()
                        .padding(.leading, 40)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sortedGroups.map { $0.id })
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .clipped()
    }
}

// MARK: - 拖放代理
struct GroupDropDelegate: DropDelegate {
    let item: NoteGroup
    let items: [NoteGroup]
    @Binding var draggingItem: NoteGroup?
    let isKnowledgeGroup: Bool
    
    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem,
              draggingItem.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggingItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        
        // 执行移动操作并添加动画
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            NoteManager.shared.moveGroup(
                from: IndexSet(integer: fromIndex),
                to: toIndex > fromIndex ? toIndex + 1 : toIndex,
                isKnowledgeGroup: isKnowledgeGroup
            )
        }
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // 限制只能垂直移动
        return DropProposal(operation: .move)
    }
}

// MARK: - 分组排序行
struct GroupSortRow: View {
    let group: NoteGroup
    let isDragging: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Image(systemName: group.icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 20)
            
            Text(group.name)
                .font(.system(size: 14))
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .opacity(isDragging ? 0 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        .padding(.vertical, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - 外观设置
struct AppearanceSettingsView: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: L10n.tr("settings.transparency"), icon: "paintbrush") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: "笔记透明度",
                            description: "设置笔记内容的透明度"
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { configManager.config.noteOpacity },
                                        set: { configManager.updateNoteOpacity($0) }
                                    ),
                                    in: 0.1...1.0,
                                    step: 0.05
                                )
                                .frame(width: 200)

                                Text("\(Int(configManager.config.noteOpacity * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        SettingsRow(
                            title: "工具栏透明度",
                            description: "设置笔记顶部工具栏的透明度"
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { configManager.config.toolbarOpacity },
                                        set: { configManager.updateToolbarOpacity($0) }
                                    ),
                                    in: 0.1...1.0,
                                    step: 0.05
                                )
                                .frame(width: 200)

                                Text("\(Int(configManager.config.toolbarOpacity * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        SettingsRow(
                            title: "分组透明度",
                            description: "设置分组区域的透明度"
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { configManager.config.groupOpacity },
                                        set: { configManager.updateGroupOpacity($0) }
                                    ),
                                    in: 0.1...1.0,
                                    step: 0.05
                                )
                                .frame(width: 200)

                                Text("\(Int(configManager.config.groupOpacity * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        SettingsRow(
                            title: L10n.tr("settings.breathingTransparency"),
                            description: L10n.tr("settings.breathingTransparencyDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { configManager.config.breathingEffectOpacity },
                                        set: { configManager.updateBreathingEffectOpacity($0) }
                                    ),
                                    in: 0.0...1.0,
                                    step: 0.05
                                )
                                .frame(width: 200)

                                Text("\(Int(configManager.config.breathingEffectOpacity * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - 关于设置
struct AboutSettingsView: View {
    @State private var showQRCode = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: showQRCode) {
            VStack(spacing: 28) {
                // 应用图标和信息
                VStack(spacing: 14) {
                    if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
                       let icon = NSImage(contentsOf: iconURL) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                    } else if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 88, height: 88)
                    }
                    
                    VStack(spacing: 4) {
                        Text("AIX")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("版本 \(AppVersion.display)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 支持作者卡片
                VStack(spacing: 16) {
                    // 头部与介绍
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.orange)
                            Text(L10n.tr("settings.supportAuthor"))
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        Text(L10n.tr("settings.supportMessage"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 16)
                    }
                    
                    // 打赏操作按钮
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showQRCode.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: showQRCode ? "chevron.up.circle.fill" : "qrcode")
                                .font(.system(size: 13, weight: .medium))
                            Text(showQRCode ? L10n.tr("settings.collapseQRCode") : L10n.tr("settings.buyCoffee"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(showQRCode ? .secondary : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(showQRCode ? Color.secondary.opacity(0.15) : Color.accentColor)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // 二维码区域（点击后平滑展开）
                    if showQRCode {
                        VStack(spacing: 10) {
                            if let imageURL = Bundle.module.url(forResource: "DonateQR", withExtension: "png"),
                               let image = NSImage(contentsOf: imageURL) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 170, height: 170)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                            }
                            
                            Text(L10n.tr("settings.scanAlipay"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                        ))
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                        )
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 通用组件
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Text(title)
                    .font(.system(size: 15, weight: .bold))
            }
            
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let description: String?
    let content: Content
    
    init(title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                
                if let description = description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            content
        }
    }
}

// MARK: - 数据库设置 UI
struct DatabaseSettingsView: View {
    @State private var dbPath: String = UserDefaults.standard.string(forKey: AppDatabase.databasePathKey) ?? AppDatabase.defaultDBPath
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showSuccessAlert = false
    @State private var successMessage = ""

    @State private var showConfirmCopyAlert = false
    @State private var pendingTargetPath: String? = nil

    @State private var showImportPreview = false
    @State private var importGroups = 0
    @State private var importNotes = 0
    @State private var importSourcePath: String? = nil
    @State private var importSourceName = ""
    @State private var showImportCompleteAlert = false
    @State private var importBackupPath: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(title: L10n.tr("settings.databaseFile"), description: L10n.tr("settings.databaseFileDesc")) {
                TextField("数据库路径", text: $dbPath)
                    .disabled(true)
                    .frame(width: 420)
            }

            HStack(spacing: 12) {
                Button(L10n.tr("settings.selectDbFolder")) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        let folder = url
                        let fm = FileManager.default

                        // 先查找默认文件名 notes.sqlite
                        let preferred = folder.appendingPathComponent("notes.sqlite")
                        var foundDB: URL? = nil

                        if fm.fileExists(atPath: preferred.path) {
                            foundDB = preferred
                        } else {
                            // 查找任意 .sqlite 或 .db 文件
                            if let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: []) {
                                foundDB = contents.first(where: { ["sqlite", "db"].contains($0.pathExtension.lowercased()) })
                            }
                        }

                        if let dbURL = foundDB {
                            // 找到已有数据库文件，直接切换
                            do {
                                try AppDatabase.shared.switchDatabase(to: dbURL.path)
                                dbPath = dbURL.path
                                successMessage = "已切换到文件夹内的数据库：\(dbURL.lastPathComponent)"
                                showSuccessAlert = true
                            } catch {
                                errorMessage = error.localizedDescription
                                showErrorAlert = true
                            }
                        } else {
                            // 未找到，准备将当前数据库复制到该文件夹中
                            let target = folder.appendingPathComponent("notes.sqlite").path
                            pendingTargetPath = target
                            showConfirmCopyAlert = true
                        }
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())

                Button(L10n.tr("button.resetToDefault")) {
                    UserDefaults.standard.removeObject(forKey: AppDatabase.databasePathKey)
                    do {
                        try AppDatabase.shared.switchDatabase(to: AppDatabase.defaultDBPath)
                        dbPath = AppDatabase.defaultDBPath
                        successMessage = "已重置为默认数据库"
                        showSuccessAlert = true
                    } catch {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
                .buttonStyle(BorderedButtonStyle())

                Button(L10n.tr("settings.importDbMerge")) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    let types = ["sqlite", "db"].compactMap { UTType(filenameExtension: $0) }
                    panel.allowedContentTypes = types
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            let (groups, notes) = try NoteStore.readFrom(path: url.path)
                            importGroups = groups.count
                            importNotes = notes.count
                            importSourcePath = url.path
                            importSourceName = url.lastPathComponent
                            showImportPreview = true
                        } catch {
                            errorMessage = error.localizedDescription
                            showErrorAlert = true
                        }
                    }
                }
                .buttonStyle(BorderedButtonStyle())
                .alert(isPresented: $showImportPreview) {
                    Alert(
                        title: Text(L10n.tr("settings.importPreview")),
                        message: Text("将从 '\(importSourceName)' 导入 \(importGroups) 个分组，\(importNotes) 个笔记。\n将先备份当前数据库，然后进行导入。是否继续？"),
                        primaryButton: .default(Text(L10n.tr("common.import")), action: {
                            guard let path = importSourcePath else { return }
                            do {
                                // 先备份当前数据库
                                let backup = try AppDatabase.shared.backupCurrentDatabase()
                                importBackupPath = backup

                                // 执行导入
                                try AppDatabase.shared.importFrom(path: path)

                                successMessage = "已导入 \(importGroups) 个分组，\(importNotes) 个笔记。备份已保存到：\(URL(fileURLWithPath: backup).lastPathComponent)"
                                showSuccessAlert = true
                            } catch {
                                errorMessage = error.localizedDescription
                                showErrorAlert = true
                            }
                        }),
                        secondaryButton: .cancel()
                    )
                }
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text(L10n.tr("common.error")), message: Text(errorMessage), dismissButton: .default(Text(L10n.tr("common.ok"))))
        }
        .alert(isPresented: $showSuccessAlert) {
            Alert(title: Text(L10n.tr("common.success")), message: Text(successMessage), dismissButton: .default(Text(L10n.tr("common.ok"))))
        }
        .alert(isPresented: $showConfirmCopyAlert) {
            Alert(
                title: Text(L10n.tr("settings.targetDbNotExist")),
                message: Text("目标路径不存在，是否将当前数据库复制并备份后切换到此位置？"),
                primaryButton: .default(Text(L10n.tr("settings.copyAndSwitch")), action: {
                    guard let path = pendingTargetPath else { return }
                    do {
                        try AppDatabase.shared.backupAndCopyCurrentDatabase(to: path)
                        try AppDatabase.shared.switchDatabase(to: path)
                        dbPath = path
                        successMessage = "已复制并切换到 \(URL(fileURLWithPath: path).lastPathComponent)"
                        showSuccessAlert = true
                    } catch {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }),
                secondaryButton: .cancel()
            )
        }
    }
}

// MARK: - 提醒设置
struct ReminderSettingsView: View {
    @StateObject private var reminderManager = ReminderManager.shared
    @State private var messageText: String = ""
    @State private var countdownTimer: Timer?
    @State private var countdownText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 启用提醒开关
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("settings.enableReminder"))
                            .font(.system(size: 13, weight: .medium))
                        
                        Text(L10n.tr("settings.enableReminderDesc"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { reminderManager.smartConfig.isEnabled },
                        set: { reminderManager.updateSmartEnabled($0) }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(NSColor.controlBackgroundColor))

                if reminderManager.smartConfig.isEnabled {
                    SmartReminderSettingsView(reminderManager: reminderManager)
                }
            }
            .padding(24)
        }
        .onAppear {
            startCountdownTimer()
        }
        .onDisappear {
            stopCountdownTimer()
        }
    }

    private func startCountdownTimer() {
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                updateCountdown()
            }
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateCountdown() {
        guard let countdown = reminderManager.nextReminderCountdown else {
            countdownText = ""
            return
        }

        let minutes = Int(countdown) / 60
        let seconds = Int(countdown) % 60
        countdownText = String(format: "%02d:%02d", minutes, seconds)
    }
}

/// 智能提醒设置视图
struct SmartReminderSettingsView: View {
    @ObservedObject var reminderManager: ReminderManager

    @State private var countdownTimer: Timer?
    @State private var countdownText: String = ""

    var body: some View {
        if reminderManager.smartConfig.isEnabled {
            VStack(spacing: 24) {
                SettingsSection(title: L10n.tr("settings.instructions"), icon: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("settings.howSmartRemindersWork"))
                            .font(.headline)

                        Text(L10n.tr("settings.reminderStep1"))
                            .font(.body)

                        Text(L10n.tr("settings.reminderStep2"))
                            .font(.body)

                        Text(L10n.tr("settings.reminderStep3"))
                            .font(.body)

                        Text(L10n.tr("settings.reminderStep4"))
                            .font(.body)

                        Text(L10n.tr("settings.reminderStep5"))
                            .font(.body)
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }

                SettingsSection(title: L10n.tr("settings.smartSettings"), icon: "brain") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: L10n.tr("settings.workDuration"),
                            description: L10n.tr("settings.workDurationDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { reminderManager.smartConfig.workDuration / 60 },
                                        set: { reminderManager.updateWorkDuration(Int($0)) }
                                    ),
                                    in: SmartReminderConfig.minWorkDuration / 60...SmartReminderConfig.maxWorkDuration / 60,
                                    step: 5
                                )
                                .frame(width: 200)

                                Text(L10n.tr("settings.minutes", Int(reminderManager.smartConfig.workDuration / 60)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        SettingsRow(
                            title: L10n.tr("settings.restDuration"),
                            description: L10n.tr("settings.restDurationDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { reminderManager.smartConfig.restDuration / 60 },
                                        set: { reminderManager.updateRestDuration(Int($0)) }
                                    ),
                                    in: SmartReminderConfig.minRestDuration / 60...SmartReminderConfig.maxRestDuration / 60,
                                    step: 1
                                )
                                .frame(width: 200)

                                Text(L10n.tr("settings.minutes", Int(reminderManager.smartConfig.restDuration / 60)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        SettingsRow(
                            title: L10n.tr("settings.idleThreshold"),
                            description: L10n.tr("settings.idleThresholdDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { reminderManager.smartConfig.idleThreshold },
                                        set: { reminderManager.updateIdleThreshold(Int($0)) }
                                    ),
                                    in: 60...180,
                                    step: 1
                                )
                                .frame(width: 200)

                                Text(L10n.tr("settings.seconds", Int(reminderManager.smartConfig.idleThreshold)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        SettingsRow(
                            title: L10n.tr("settings.restRecognition"),
                            description: L10n.tr("settings.restRecognitionDesc")
                        ) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { reminderManager.smartConfig.restRecognitionTime / 60 },
                                        set: { reminderManager.updateRestRecognitionTime($0) }
                                    ),
                                    in: (reminderManager.smartConfig.restDuration * 0.6)/60...(reminderManager.smartConfig.restDuration)/60,
                                    step: 0.1
                                )
                                .frame(width: 200)

                                Text({
                                    let seconds = Int(reminderManager.smartConfig.restRecognitionTime)
                                    let m = seconds / 60
                                    let s = seconds % 60
                                    if m > 0 {
                                        return L10n.tr("settings.minutesAndSeconds", m, s)
                                    } else {
                                        return L10n.tr("settings.seconds", s)
                                    }
                                }())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 倒计时显示（距离下一次休息）
                if !countdownText.isEmpty {
                    HStack {
                        Text(L10n.tr("settings.untilBreak"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        Text(countdownText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }



                SettingsSection(title: L10n.tr("settings.reminderContent"), icon: "text.bubble") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(
                            title: L10n.tr("settings.reminderMessage"),
                            description: L10n.tr("settings.reminderMessageDesc")
                        ) {
                            TextField(
                                "",
                                text: Binding(
                                    get: { reminderManager.smartConfig.reminderMessage },
                                    set: { reminderManager.updateSmartReminderMessage($0) }
                                )
                            )
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 250)
                        }

                        SettingsRow(
                            title: L10n.tr("settings.reminderSound"),
                            description: L10n.tr("settings.reminderSoundDesc")
                        ) {
                            Picker("", selection: Binding(
                                get: { reminderManager.smartConfig.soundName },
                                set: { reminderManager.updateSmartReminderSound($0) }
                            )) {
                                ForEach(getSystemSounds(), id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 180)
                        }

                        SettingsRow(
                            title: L10n.tr("settings.restEndSound"),
                            description: L10n.tr("settings.restEndSoundDesc")
                        ) {
                            Picker("", selection: Binding(
                                get: { reminderManager.smartConfig.restEndSoundName },
                                set: { reminderManager.updateRestEndSound($0) }
                            )) {
                                ForEach(getSystemSounds(), id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 180)
                        }

                        SettingsRow(
                            title: L10n.tr("settings.testReminder"),
                            description: L10n.tr("settings.testReminderDesc")
                        ) {
                            Button(L10n.tr("common.test")) {
                                reminderManager.testReminder()
                            }
                            .buttonStyle(BorderedButtonStyle())
                        }
                    }
                }


            }
            .onAppear {
                startSmartCountdownTimer()
            }
            .onDisappear {
                stopSmartCountdownTimer()
            }
        }
    }

    private func startSmartCountdownTimer() {
        updateSmartCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                updateSmartCountdown()
            }
        }
    }

    private func stopSmartCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateSmartCountdown() {
        guard let countdown = reminderManager.nextSmartReminderCountdown else {
            countdownText = ""
            return
        }

        let minutes = Int(countdown) / 60
        let seconds = Int(countdown) % 60
        countdownText = String(format: "%02d:%02d", minutes, seconds)
    }
}

/// 快捷键设置视图
struct HotkeySettingsView: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @State private var isRecording = false
    @State private var recordedHotkey = ""
    @FocusState private var isHotkeyFieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            SettingsSection(title: L10n.tr("settings.globalHotkeys"), icon: "keyboard") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsRow(
                        title: L10n.tr("settings.showHideAIX"),
                        description: L10n.tr("settings.showHideAIXDesc")
                    ) {
                        HStack(spacing: 8) {
                            Text(recordedHotkey.isEmpty ? configManager.config.toggleAIXHotkey : recordedHotkey)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                                .onTapGesture {
                                    isRecording = true
                                    isHotkeyFieldFocused = true
                                    recordedHotkey = ""
                                }
                                .focused($isHotkeyFieldFocused)

                            Button(action: {
                                isRecording = true
                                isHotkeyFieldFocused = true
                                recordedHotkey = ""
                            }) {
                                Text(isRecording ? "请按下快捷键..." : "修改")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    if isRecording {
                        Text(L10n.tr("settings.pressHotkey"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onAppear {
                recordedHotkey = ""
            }
        }
        .onExitCommand {
            if isRecording {
                isRecording = false
                isHotkeyFieldFocused = false
                recordedHotkey = ""
            }
        }
        .background(
            HotkeyRecorder(
                isRecording: $isRecording,
                recordedHotkey: $recordedHotkey,
                onHotkeyRecorded: { hotkey in
                    configManager.updateToggleAIXHotkey(hotkey)
                    isRecording = false
                    isHotkeyFieldFocused = false
                    recordedHotkey = ""
                }
            )
        )
    }
}

/// 快捷键录制器
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var recordedHotkey: String
    var onHotkeyRecorded: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateState(isRecording: isRecording, recordedHotkey: recordedHotkey)
        if isRecording && context.coordinator.monitor == nil {
            context.coordinator.startMonitoring()
        } else if !isRecording && context.coordinator.monitor != nil {
            context.coordinator.stopMonitoring()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording, recordedHotkey: $recordedHotkey, onHotkeyRecorded: onHotkeyRecorded)
    }

    class Coordinator {
        var isRecording: Bool
        var recordedHotkey: String
        var onHotkeyRecorded: (String) -> Void
        var monitor: Any?

        init(isRecording: Binding<Bool>, recordedHotkey: Binding<String>, onHotkeyRecorded: @escaping (String) -> Void) {
            self.isRecording = isRecording.wrappedValue
            self.recordedHotkey = recordedHotkey.wrappedValue
            self.onHotkeyRecorded = onHotkeyRecorded
        }

        func updateState(isRecording: Bool, recordedHotkey: String) {
            self.isRecording = isRecording
            self.recordedHotkey = recordedHotkey
        }

        func startMonitoring() {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isRecording else { return }

                var modifiers: [String] = []

                if event.modifierFlags.contains(.command) {
                    modifiers.append("Cmd")
                }
                if event.modifierFlags.contains(.shift) {
                    modifiers.append("Shift")
                }
                if event.modifierFlags.contains(.option) {
                    modifiers.append("Option")
                }
                if event.modifierFlags.contains(.control) {
                    modifiers.append("Control")
                }

                if !modifiers.isEmpty {
                    let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
                    if !key.isEmpty {
                        let hotkey = modifiers.joined(separator: "+") + "+" + key
                        self.onHotkeyRecorded(hotkey)
                        return
                    }
                }
            }
        }

        func stopMonitoring() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stopMonitoring()
        }
    }
}


// MARK: - Helper Functions
func getSystemSounds() -> [String] {
    // macOS 内置的系统提示音
    return [
        "Basso",
        "Blow",
        "Bottle",
        "Frog",
        "Funk",
        "Glass",
        "Hero",
        "Morse",
        "Ping",
        "Pop",
        "Purr",
        "Sosumi",
        "Submarine",
        "Tink"
    ]
}

// MARK: - 自动隐藏设置

struct AutoHideSettingsSection: View {
    @State private var isEnabled: Bool = AutoHideManager.shared.isEnabled
    @State private var timeoutMinutes: Double = AutoHideManager.shared.timeout / 60.0
    @State private var excludedApps: Set<String> = AutoHideManager.shared.excludedApps
    @State private var showAppPicker = false
    
    var body: some View {
        SettingsSection(title: L10n.tr("settings.appAutoHide"), icon: "eye.slash") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsRow(
                    title: L10n.tr("settings.enableAutoHide"),
                    description: L10n.tr("settings.enableAutoHideDesc")
                ) {
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .onChange(of: isEnabled) { _, newValue in
                            AutoHideManager.shared.isEnabled = newValue
                        }
                }
                
                if isEnabled {
                    SettingsRow(
                        title: L10n.tr("settings.timeout"),
                        description: L10n.tr("settings.timeoutDesc")
                    ) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Slider(value: $timeoutMinutes, in: 20...60, step: 5)
                                .frame(width: 200)
                                .onChange(of: timeoutMinutes) { _, newValue in
                                    AutoHideManager.shared.timeout = newValue * 60.0
                                }
                            
                            Text("\(Int(timeoutMinutes)) 分钟")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    SettingsRow(
                        title: L10n.tr("settings.excludedApps"),
                        description: L10n.tr("settings.excludedAppsDesc")
                    ) {
                        Button(L10n.tr("common.manage")) {
                            showAppPicker = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if !excludedApps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(excludedApps).sorted(), id: \.self) { bundleId in
                                HStack(spacing: 8) {
                                    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
                                       let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                    } else {
                                        Image(systemName: "app.fill")
                                            .frame(width: 18, height: 18)
                                    }
                                    
                                    Text(appName(for: bundleId))
                                        .font(.system(size: 12))
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        AutoHideManager.shared.removeExcludedApp(bundleId)
                                        excludedApps = AutoHideManager.shared.excludedApps
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $showAppPicker) {
            AutoHideAppPickerView(excludedApps: $excludedApps)
        }
    }
    
    private func appName(for bundleId: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            return app.localizedName ?? bundleId
        }
        // 从 bundle ID 猜测名称
        return bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    }
}

struct AutoHideAppPickerView: View {
    @Binding var excludedApps: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [(name: String, bundleId: String, icon: NSImage)] = []
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("settings.selectExcludedApps"))
                    .font(.headline)
                Spacer()
                Button(L10n.tr("common.done")) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            if apps.isEmpty {
                VStack(spacing: 8) {
                    Text(L10n.tr("settings.noManageableApps"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(apps, id: \.bundleId) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                            
                            Text(app.name)
                                .font(.system(size: 13))
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { excludedApps.contains(app.bundleId) },
                                set: { isExcluded in
                                    if isExcluded {
                                        AutoHideManager.shared.addExcludedApp(app.bundleId)
                                    } else {
                                        AutoHideManager.shared.removeExcludedApp(app.bundleId)
                                    }
                                    excludedApps = AutoHideManager.shared.excludedApps
                                }
                            ))
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .frame(width: 360, height: 400)
        .onAppear {
            apps = AutoHideManager.shared.getManageableApps()
        }
    }
}

// MARK: - 快捷键配置部分
struct HotkeyConfigurationSection: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @State private var hotkeyInput = ""
    @State private var colorPickerHotkeyInput = ""
    @State private var translationHotkeyInput = ""
    @State private var isEditingHotkey = false
    @State private var isEditingColorPickerHotkey = false
    @State private var isEditingTranslationHotkey = false
    private let defaultHotkey = "Control+Shift+Cmd+X"
    private let defaultColorPickerHotkey = "Cmd+Shift+P"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsRow(
                title: L10n.tr("settings.showHideButton"),
                description: L10n.tr("settings.showHideButtonDesc")
            ) {
                HStack(spacing: 8) {
                    TextField("例如：Control+Shift+Cmd+O", text: $hotkeyInput)
                        .disabled(!isEditingHotkey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 180)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            if !hotkeyInput.isEmpty && isEditingHotkey {
                                configManager.updateToggleAIXHotkey(hotkeyInput)
                                isEditingHotkey = false
                            }
                        }

                    Button(action: {
                        if isEditingHotkey {
                            if !hotkeyInput.isEmpty {
                                configManager.updateToggleAIXHotkey(hotkeyInput)
                                isEditingHotkey = false
                            }
                        } else {
                            isEditingHotkey = true
                        }
                    }) {
                        Text(isEditingHotkey ? "保存" : "修改")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isEditingHotkey ? 
                                Color.accentColor.opacity(0.2) : 
                                Color.gray.opacity(0.2)
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            SettingsRow(
                title: L10n.tr("settings.colorPickerHotkey"),
                description: L10n.tr("settings.colorPickerHotkeyDesc")
            ) {
                HStack(spacing: 8) {
                    TextField("例如：Cmd+Shift+P", text: $colorPickerHotkeyInput)
                        .disabled(!isEditingColorPickerHotkey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 180)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            if !colorPickerHotkeyInput.isEmpty && isEditingColorPickerHotkey {
                                configManager.updateColorPickerHotkey(colorPickerHotkeyInput)
                                isEditingColorPickerHotkey = false
                            }
                        }

                    Button(action: {
                        if isEditingColorPickerHotkey {
                            if !colorPickerHotkeyInput.isEmpty {
                                configManager.updateColorPickerHotkey(colorPickerHotkeyInput)
                                isEditingColorPickerHotkey = false
                            }
                        } else {
                            isEditingColorPickerHotkey = true
                        }
                    }) {
                        Text(isEditingColorPickerHotkey ? "保存" : "修改")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isEditingColorPickerHotkey ? 
                                Color.accentColor.opacity(0.2) : 
                                Color.gray.opacity(0.2)
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            HStack(spacing: 0) {
                Text(L10n.tr("settings.currentHotkey"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(configManager.config.toggleAIXHotkey)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.accentColor)
                Spacer()
                Button(action: {
                    configManager.updateToggleAIXHotkey(defaultHotkey)
                    hotkeyInput = defaultHotkey
                    isEditingHotkey = false
                }) {
                    Text(L10n.tr("common.reset"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(3)
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack(spacing: 0) {
                Text(L10n.tr("settings.colorPickerHotkeyLabel"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(configManager.config.colorPickerHotkey)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.accentColor)
                Spacer()
                Button(action: {
                    configManager.updateColorPickerHotkey(defaultColorPickerHotkey)
                    colorPickerHotkeyInput = defaultColorPickerHotkey
                    isEditingColorPickerHotkey = false
                }) {
                    Text(L10n.tr("common.reset"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(3)
                }
                .buttonStyle(PlainButtonStyle())
            }

            SettingsRow(
                title: "翻译快捷键",
                description: "选中文本后按此快捷键翻译"
            ) {
                HStack(spacing: 8) {
                    TextField("例如：Cmd+Shift+T", text: $translationHotkeyInput)
                        .disabled(!isEditingTranslationHotkey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 180)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            if !translationHotkeyInput.isEmpty && isEditingTranslationHotkey {
                                configManager.updateTranslationHotkey(translationHotkeyInput)
                                isEditingTranslationHotkey = false
                            }
                        }

                    Button(action: {
                        if isEditingTranslationHotkey {
                            if !translationHotkeyInput.isEmpty {
                                configManager.updateTranslationHotkey(translationHotkeyInput)
                                isEditingTranslationHotkey = false
                            }
                        } else {
                            isEditingTranslationHotkey = true
                        }
                    }) {
                        Text(isEditingTranslationHotkey ? "保存" : "修改")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isEditingTranslationHotkey ?
                                Color.accentColor.opacity(0.2) :
                                Color.gray.opacity(0.2)
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            HStack(spacing: 0) {
                Text("当前翻译快捷键：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(configManager.config.translationHotkey.isEmpty ? "未设置" : configManager.config.translationHotkey)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(configManager.config.translationHotkey.isEmpty ? .secondary : .accentColor)
                Spacer()
                if !configManager.config.translationHotkey.isEmpty {
                    Button(action: {
                        configManager.updateTranslationHotkey("")
                        translationHotkeyInput = ""
                        isEditingTranslationHotkey = false
                    }) {
                        Text("清除")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // 修饰键快速复制按钮
            HStack(spacing: 8) {
                Text(L10n.tr("settings.quickModifiers"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(["Control", "Shift", "Cmd", "Option"], id: \.self) { modifier in
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(modifier, forType: .string)
                    }) {
                        Text(modifier)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(L10n.tr("settings.clickToCopy", modifier))
                }
            }
            .padding(.vertical, 4)
            
            Text(L10n.tr("settings.hotkeyFormatHint"))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // 权限提示（虽然快捷键不再强依赖辅助功能，但 InputMonitor 仍然需要）
            if !InputMonitor.hasAccessibilityPermission() {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text(L10n.tr("settings.accessibilityNote"))
                        .font(.system(size: 10))
                    Spacer()
                    Button(L10n.tr("settings.clickToAuth")) {
                        InputMonitor.promptForAccessibilityPermission()
                    }
                    .buttonStyle(.link)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(Color.blue.opacity(0.05))
            }
        }
        .onAppear {
            hotkeyInput = configManager.config.toggleAIXHotkey
            colorPickerHotkeyInput = configManager.config.colorPickerHotkey
            translationHotkeyInput = configManager.config.translationHotkey
            isEditingHotkey = false
            isEditingColorPickerHotkey = false
            isEditingTranslationHotkey = false
        }
    }
}

// MARK: - 快捷键配置行
struct HotkeyConfigurationRow: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @State private var isRecording = false
    @State private var recordedHotkey = ""
    @FocusState private var isHotkeyFieldFocused: Bool

    var body: some View {
        SettingsRow(
            title: "显示/隐藏悬浮球",
            description: "设置用于显示或隐藏未被单独隐藏的悬浮球的快捷键"
        ) {
            HStack(spacing: 8) {
                Text(recordedHotkey.isEmpty ? configManager.config.toggleAIXHotkey : recordedHotkey)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    .onTapGesture {
                        isRecording = true
                        isHotkeyFieldFocused = true
                        recordedHotkey = ""
                    }
                    .focused($isHotkeyFieldFocused)

                Button(action: {
                    isRecording = true
                    isHotkeyFieldFocused = true
                    recordedHotkey = ""
                }) {
                    Text(isRecording ? "请按下快捷键..." : "修改")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .onExitCommand {
            if isRecording {
                isRecording = false
                isHotkeyFieldFocused = false
                recordedHotkey = ""
            }
        }
        .background(
            HotkeyRecorder(
                isRecording: $isRecording,
                recordedHotkey: $recordedHotkey,
                onHotkeyRecorded: { hotkey in
                    configManager.updateToggleAIXHotkey(hotkey)
                    isRecording = false
                    isHotkeyFieldFocused = false
                    recordedHotkey = ""
                }
            )
        )
    }
}

// MARK: - AI 设置
struct AISettingsView: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @ObservedObject private var aiService = AIService.shared
    @State private var opencodeModels: [String] = []
    @State private var isLoadingModels = false
    
    // AI 提供商预设
    enum AIPreset: String, CaseIterable {
        case openai = "OpenAI"
        case deepseek = "DeepSeek"
        case custom = "自定义"

        var localizedName: String {
            switch self {
            case .openai: return "OpenAI"
            case .deepseek: return "DeepSeek"
            case .custom: return L10n.tr("config.custom")
            }
        }

        var url: String {
            switch self {
            case .openai: return "https://api.openai.com/v1"
            case .deepseek: return "https://api.deepseek.com"
            case .custom: return ""
            }
        }
        
        var model: String {
            switch self {
            case .openai: return "gpt-4o-mini"
            case .deepseek: return "deepseek-chat"
            case .custom: return ""
            }
        }
    }
    
    private var currentPreset: AIPreset {
        let url = configManager.config.aiUrl
        if url == AIPreset.openai.url { return .openai }
        if url == AIPreset.deepseek.url || url == "https://api.deepseek.com/v1" { return .deepseek }
        return .custom
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // AI 模式选择
                SettingsSection(title: L10n.tr("settings.aiMode"), icon: "cpu") {
                    SettingsRow(
                        title: L10n.tr("settings.aiBackend"),
                        description: L10n.tr("settings.aiBackendDesc")
                    ) {
                        Picker("", selection: Binding(
                            get: { configManager.config.aiMode },
                            set: { configManager.updateAiMode($0) }
                        )) {
                            ForEach(FloatingButtonConfig.AIMode.allCases, id: \.self) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
                
                if configManager.config.aiMode == .api {
                    apiSettingsSection
                } else {
                    opencodeSettingsSection
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - API 模式设置
    private var apiSettingsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: L10n.tr("settings.aiProvider"), icon: "sparkles") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsRow(
                        title: L10n.tr("settings.preset"),
                        description: L10n.tr("settings.presetDesc")
                    ) {
                        Picker("", selection: Binding(
                            get: { currentPreset },
                            set: { preset in
                                if preset != .custom {
                                    configManager.updateAiUrl(preset.url)
                                    configManager.updateAiModel(preset.model)
                                }
                            }
                        )) {
                            ForEach(AIPreset.allCases, id: \.self) { preset in
                                Text(preset.localizedName).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                    
                    SettingsRow(
                        title: "API URL",
                        description: L10n.tr("settings.apiEndpointDesc")
                    ) {
                        TextField("https://api.openai.com/v1", text: Binding(
                            get: { configManager.config.aiUrl },
                            set: { configManager.updateAiUrl($0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 250)
                    }
                    
                    SettingsRow(
                        title: L10n.tr("settings.model"),
                        description: L10n.tr("settings.modelDesc")
                    ) {
                        TextField("gpt-4o-mini", text: Binding(
                            get: { configManager.config.aiModel },
                            set: { configManager.updateAiModel($0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 250)
                    }
                    
                    SettingsRow(
                        title: "API Key",
                        description: L10n.tr("settings.apiKeyDesc")
                    ) {
                        SecureField("sk-...", text: Binding(
                            get: { configManager.config.aiApiKey },
                            set: { configManager.updateAiApiKey($0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 250)
                    }
                    
                    SettingsRow(
                        title: L10n.tr("settings.systemPrompt"),
                        description: L10n.tr("settings.systemPromptDesc")
                    ) {
                        TextField("你是一个知识问答助手...", text: Binding(
                            get: { configManager.config.aiSystemPrompt },
                            set: { configManager.updateAiSystemPrompt($0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 250)
                    }
                }
            }
            
            SettingsSection(title: L10n.tr("settings.instructions"), icon: "info.circle") {
                Text(L10n.tr("settings.apiModeInstructions"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - opencode 模式设置
    private var opencodeSettingsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: L10n.tr("settings.opencodeConfig"), icon: "terminal") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsRow(
                        title: L10n.tr("settings.model"),
                        description: L10n.tr("settings.opencodeModelDesc")
                    ) {
                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { configManager.config.opencodeModel },
                                set: { configManager.updateOpencodeModel($0) }
                            )) {
                                if opencodeModels.isEmpty && !isLoadingModels {
                                    Text(configManager.config.opencodeModel.isEmpty ? "点击刷新获取" : configManager.config.opencodeModel)
                                        .tag(configManager.config.opencodeModel)
                                }
                                ForEach(opencodeModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .frame(width: 220)
                            
                            Button(action: { fetchOpencodeModels() }) {
                                if isLoadingModels {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12))
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(isLoadingModels)
                            .help(L10n.tr("settings.refreshModels"))
                        }
                    }
                }
            }
            .onAppear { fetchOpencodeModels() }
            
            // ACP 服务控制
            SettingsSection(title: L10n.tr("settings.acpService"), icon: "point.3.connected.trianglepath.dotted") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsRow(
                        title: L10n.tr("settings.status"),
                        description: L10n.tr("settings.statusDesc")
                    ) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(acpStatusColor)
                                .frame(width: 8, height: 8)
                            Text(AIService.shared.acpStatus.localizedName)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            
                            Spacer().frame(width: 8)
                            
                            if AIService.shared.acpStatus == .disconnected {
                                Button(L10n.tr("common.start")) {
                                    Task {
                                        await AIService.shared.connectACP()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else if AIService.shared.acpStatus == .connected {
                                Button(L10n.tr("common.stop")) {
                                    Task {
                                        await AIService.shared.disconnectACP()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    
                    SettingsRow(
                        title: L10n.tr("settings.autoStart"),
                        description: L10n.tr("settings.autoStartDesc")
                    ) {
                        Toggle("", isOn: Binding(
                            get: { configManager.config.acpAutoStart },
                            set: { configManager.updateAcpAutoStart($0) }
                        ))
                        .toggleStyle(.switch)
                    }
                }
            }
            
            SettingsSection(title: "说明", icon: "info.circle") {
                Text("opencode 模式通过本地 opencode CLI 工具调用 AI，无需 API Key。请确保已安装 opencode（brew install opencode 或 npm i -g opencode）。\n\n免费模型：opencode/kimi-k2.5-free、opencode/minimax-m2.1-free 等。\n\n启动 ACP 服务可减少首次 AI 查询的延迟。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }
    
    /// ACP 状态对应的颜色
    private var acpStatusColor: Color {
        switch AIService.shared.acpStatus {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        }
    }
    
    private func fetchOpencodeModels() {
        isLoadingModels = true
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/opencode")
            process.arguments = ["models"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let models = output.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasSuffix("-free") }
                
                await MainActor.run {
                    self.opencodeModels = models
                    if !models.isEmpty && self.configManager.config.opencodeModel.isEmpty {
                        self.configManager.updateOpencodeModel(models[0])
                    }
                    self.isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingModels = false
                }
            }
        }
    }
}

// MARK: - 备份设置
struct BackupSettingsView: View {
    @ObservedObject private var configManager = BackupConfigManager.shared
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showBackupList = false
    @State private var availableBackups: [BackupInfo] = []
    @State private var isBackingUp = false
    @State private var showRestoreConfirm = false
    @State private var selectedBackup: BackupInfo?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 启用自动备份
            SettingsRow(
                title: L10n.tr("settings.autoBackup"),
                description: L10n.tr("settings.autoBackupDesc")
            ) {
                Toggle("", isOn: Binding(
                    get: { configManager.config.isEnabled },
                    set: { configManager.updateEnabled($0) }
                ))
                .labelsHidden()
            }
            
            if configManager.config.isEnabled {
                // 备份频率
                SettingsRow(
                    title: L10n.tr("settings.backupFrequency"),
                    description: L10n.tr("settings.backupFrequencyDesc")
                ) {
                    Picker("", selection: Binding(
                        get: { configManager.config.frequency },
                        set: { configManager.updateFrequency($0) }
                    )) {
                        ForEach(BackupFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 120)
                }
                
                // 备份时间（仅非手动模式）
                if configManager.config.frequency != .manual {
                    SettingsRow(
                        title: L10n.tr("settings.backupTime"),
                        description: L10n.tr("settings.backupTimeDesc")
                    ) {
                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { configManager.config.backupHour },
                                set: { hour in
                                    configManager.updateBackupTime(hour: hour, minute: configManager.config.backupMinute)
                                }
                            )) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(String(format: "%02d", hour)).tag(hour)
                                }
                            }
                            .frame(width: 70)
                            
                            Text(":")
                            
                            Picker("", selection: Binding(
                                get: { configManager.config.backupMinute },
                                set: { minute in
                                    configManager.updateBackupTime(hour: configManager.config.backupHour, minute: minute)
                                }
                            )) {
                                ForEach(0..<60, id: \.self) { minute in
                                    Text(String(format: "%02d", minute)).tag(minute)
                                }
                            }
                            .frame(width: 70)
                        }
                    }
                }
            }
            
            // 备份路径
            SettingsRow(
                title: L10n.tr("settings.backupPath"),
                description: L10n.tr("settings.backupPathDesc")
            ) {
                HStack(spacing: 8) {
                    TextField("选择备份文件夹", text: Binding(
                        get: { configManager.config.backupPath },
                        set: { _ in }
                    ))
                    .disabled(true)
                    .frame(minWidth: 200, maxWidth: .infinity)
                    
                    Button(L10n.tr("common.browse")) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            configManager.updateBackupPath(url.path)
                        }
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .frame(minWidth: 70)
                }
            }
            
            // 最大备份数
            SettingsRow(
                title: L10n.tr("settings.maxBackups"),
                description: L10n.tr("settings.maxBackupsDesc")
            ) {
                HStack(spacing: 8) {
                    Stepper(value: Binding(
                        get: { configManager.config.maxBackups },
                        set: { configManager.updateMaxBackups($0) }
                    ), in: 1...100) {
                        Text(L10n.tr("settings.backupCount", configManager.config.maxBackups))
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
            
            // 上次备份时间
            if let lastBackupTime = configManager.config.lastBackupTime {
                SettingsRow(
                    title: L10n.tr("settings.lastBackup"),
                    description: L10n.tr("settings.lastBackupDesc")
                ) {
                    Text(formatDate(lastBackupTime))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // 操作按钮
            HStack(spacing: 12) {
                Button(L10n.tr("settings.backupNow")) {
                    performBackup()
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(configManager.config.backupPath.isEmpty || isBackingUp)
                
                Button(L10n.tr("settings.viewBackups")) {
                    loadBackups()
                    showBackupList = true
                }
                .buttonStyle(BorderedButtonStyle())
                .disabled(configManager.config.backupPath.isEmpty)
                
                if isBackingUp {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
        .alert(L10n.tr("common.success"), isPresented: $showSuccessAlert) {
            Button(L10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .alert(L10n.tr("common.error"), isPresented: $showErrorAlert) {
            Button(L10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert(L10n.tr("settings.confirmRestore"), isPresented: $showRestoreConfirm) {
            Button(L10n.tr("common.cancel"), role: .cancel) {}
            Button(L10n.tr("settings.confirmRestore"), role: .destructive) {
                if let backup = selectedBackup {
                    restoreBackup(backup)
                }
            }
        } message: {
            if let backup = selectedBackup {
                Text("确定要从备份\n\(backup.displayName)\n恢复吗？\n\n当前数据会先被备份，然后替换为备份的内容。")
            }
        }
        .sheet(isPresented: $showBackupList) {
            BackupListView(
                backups: $availableBackups,
                onRestore: { backup in
                    selectedBackup = backup
                    showRestoreConfirm = true
                    showBackupList = false
                },
                onDelete: { backup in
                    deleteBackup(backup)
                }
            )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func performBackup() {
        isBackingUp = true
        
        Task { @MainActor in
            do {
                let backupPath = try BackupManager.shared.performBackup()
                successMessage = "备份成功！\n\n备份位置：\(backupPath)"
                showSuccessAlert = true
            } catch {
                errorMessage = "备份失败：\(error.localizedDescription)"
                showErrorAlert = true
            }
            isBackingUp = false
        }
    }
    
    private func loadBackups() {
        availableBackups = BackupManager.shared.getAvailableBackups()
    }
    
    private func restoreBackup(_ backup: BackupInfo) {
        Task { @MainActor in
            do {
                try BackupManager.shared.restore(from: backup)
                successMessage = "恢复成功！应用将重新加载数据。"
                showSuccessAlert = true
            } catch {
                errorMessage = "恢复失败：\(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    private func deleteBackup(_ backup: BackupInfo) {
        do {
            try FileManager.default.removeItem(atPath: backup.path)
            loadBackups()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

// MARK: - 备份列表视图
struct BackupListView: View {
    @Binding var backups: [BackupInfo]
    let onRestore: (BackupInfo) -> Void
    let onDelete: (BackupInfo) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(L10n.tr("settings.backupList"))
                    .font(.headline)
                Spacer()
                Button(L10n.tr("common.close")) {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // 备份列表
            if backups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(L10n.tr("settings.noBackups"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(backups) { backup in
                        BackupRowView(
                            backup: backup,
                            onRestore: { onRestore(backup) },
                            onDelete: { onDelete(backup) }
                        )
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
    }
}

// MARK: - 备份行视图
struct BackupRowView: View {
    let backup: BackupInfo
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.displayName)
                    .font(.system(size: 14, weight: .medium))
                
                HStack(spacing: 8) {
                    if let appVersion = backup.appVersion {
                        Label(appVersion, systemImage: "app.badge")
                    }
                    Label("\(backup.noteCount) 笔记", systemImage: "note.text")
                    Label("\(backup.groupCount) 分组", systemImage: "folder")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if !backup.isValid {
                    Label(L10n.tr("settings.backupCorrupted"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(L10n.tr("common.restore")) {
                    onRestore()
                }
                .buttonStyle(BorderedButtonStyle())
                .disabled(!backup.isValid)
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 浏览器列表管理视图
struct BrowserListManagementView: View {
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @State private var allBrowsers: [BrowserInfo] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("浏览器列表")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("拖拽调整顺序，取消勾选以隐藏")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
            
            if allBrowsers.isEmpty {
                Text("未检测到其他浏览器")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(sortedBrowsers) { browser in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { !configManager.config.hiddenBrowsers.contains(browser.id) },
                                set: { enabled in
                                    var hidden = configManager.config.hiddenBrowsers
                                    if enabled {
                                        hidden.removeAll { $0 == browser.id }
                                    } else {
                                        hidden.append(browser.id)
                                    }
                                    configManager.updateHiddenBrowsers(hidden)
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            
                            Image(nsImage: browser.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                            
                            Text(browser.name)
                                .font(.system(size: 13))
                                .foregroundColor(configManager.config.hiddenBrowsers.contains(browser.id) ? .secondary : .primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove(perform: moveBrowser)
                }
                .listStyle(.bordered)
                .frame(height: min(CGFloat(allBrowsers.count) * 36 + 8, 220))
            }
        }
        .onAppear {
            allBrowsers = BrowserDetector.shared.detectAllBrowsers()
        }
    }
    
    /// 按配置排序的浏览器列表
    private var sortedBrowsers: [BrowserInfo] {
        let order = configManager.config.browserOrder
        if order.isEmpty { return allBrowsers }
        
        return allBrowsers.sorted { a, b in
            let indexA = order.firstIndex(of: a.id) ?? Int.max
            let indexB = order.firstIndex(of: b.id) ?? Int.max
            if indexA != indexB { return indexA < indexB }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    
    /// 拖拽排序
    private func moveBrowser(from source: IndexSet, to destination: Int) {
        var sorted = sortedBrowsers
        sorted.move(fromOffsets: source, toOffset: destination)
        let newOrder = sorted.map { $0.id }
        configManager.updateBrowserOrder(newOrder)
    }
}

// MARK: - 全局密码设置
struct GlobalPasswordSettingsView: View {
    @ObservedObject private var noteManager = NoteManager.shared
    @State private var currentStep: PasswordStep = .idle
    @State private var inputPassword = ""
    @State private var confirmPassword = ""
    @State private var securityQuestion = ""
    @State private var securityAnswer = ""
    @State private var verifyPassword = ""
    @State private var errorMessage = ""
    
    enum PasswordStep {
        case idle          // 初始状态
        case setting       // 设置新密码（首次或修改）
        case verifyOld     // 验证旧密码（修改前）
        case resetByQuestion // 通过安全问题重置
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if noteManager.hasGlobalPassword {
                // 已设置密码
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("已设置全局密码")
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                // 自动锁定时间设置
                HStack(spacing: 8) {
                    Text("自动锁定")
                        .font(.subheadline)
                    Picker("", selection: Binding(
                        get: { noteManager.autoLockMinutes },
                        set: { noteManager.saveAutoLockMinutes($0) }
                    )) {
                        Text("不自动锁定").tag(0)
                        Text("1 分钟").tag(1)
                        Text("3 分钟").tag(3)
                        Text("5 分钟").tag(5)
                        Text("10 分钟").tag(10)
                        Text("30 分钟").tag(30)
                    }
                    .frame(width: 140)
                }
                
                switch currentStep {
                case .idle:
                    HStack(spacing: 12) {
                        Button("修改密码") {
                            resetFields()
                            currentStep = .verifyOld
                        }
                        Button("移除密码") {
                            resetFields()
                            currentStep = .verifyOld
                        }
                        .foregroundColor(.red)
                        Button("忘记密码？") {
                            resetFields()
                            if let q = noteManager.globalSecurityQuestion, !q.isEmpty {
                                securityQuestion = q
                                currentStep = .resetByQuestion
                            } else {
                                errorMessage = "未设置安全问题，无法找回"
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                case .verifyOld:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("请输入当前密码")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack {
                            SecureField("当前密码", text: $verifyPassword)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                            Button("确认") {
                                if noteManager.verifyGlobalPassword(verifyPassword) {
                                    currentStep = .setting
                                    verifyPassword = ""
                                    errorMessage = ""
                                } else {
                                    errorMessage = "密码错误"
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("取消") {
                                resetFields()
                                currentStep = .idle
                            }
                        }
                    }
                    
                case .setting:
                    setPasswordForm(isNew: false)
                    
                case .resetByQuestion:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("安全问题：\(securityQuestion)")
                            .font(.subheadline)
                        TextField("输入答案", text: $securityAnswer)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                        HStack {
                            Button("验证并重置") {
                                if noteManager.verifySecurityAnswer(securityAnswer) {
                                    noteManager.removeGlobalPassword()
                                    resetFields()
                                    currentStep = .idle
                                    errorMessage = ""
                                } else {
                                    errorMessage = "答案错误"
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("取消") {
                                resetFields()
                                currentStep = .idle
                            }
                        }
                    }
                }
                
            } else {
                // 未设置密码
                HStack {
                    Image(systemName: "lock.open")
                        .foregroundColor(.secondary)
                    Text("未设置全局密码")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                if currentStep == .idle {
                    Button("设置密码") {
                        resetFields()
                        currentStep = .setting
                    }
                } else if currentStep == .setting {
                    setPasswordForm(isNew: true)
                }
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
    
    @ViewBuilder
    private func setPasswordForm(isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isNew ? "设置新密码" : "设置新密码（已验证）")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                SecureField("输入密码", text: $inputPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                SecureField("确认密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            
            HStack(spacing: 8) {
                TextField("安全问题（如：我的宠物叫什么）", text: $securityQuestion)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                TextField("答案", text: $securityAnswer)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }
            
            HStack(spacing: 12) {
                Button(isNew ? "确定设置" : "保存修改") {
                    if inputPassword.isEmpty {
                        errorMessage = "密码不能为空"
                    } else if inputPassword != confirmPassword {
                        errorMessage = "两次输入不一致"
                    } else if securityQuestion.isEmpty || securityAnswer.isEmpty {
                        errorMessage = "请填写安全问题和答案"
                    } else {
                        noteManager.setupGlobalPassword(
                            password: inputPassword,
                            question: securityQuestion,
                            answer: securityAnswer
                        )
                        resetFields()
                        currentStep = .idle
                        errorMessage = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                
                if !isNew {
                    Button("移除密码") {
                        noteManager.removeGlobalPassword()
                        resetFields()
                        currentStep = .idle
                        errorMessage = ""
                    }
                    .foregroundColor(.red)
                }
                
                Button("取消") {
                    resetFields()
                    currentStep = .idle
                    errorMessage = ""
                }
            }
        }
    }
    
    private func resetFields() {
        inputPassword = ""
        confirmPassword = ""
        securityQuestion = ""
        securityAnswer = ""
        verifyPassword = ""
        errorMessage = ""
    }
}


#Preview {

    SettingsView()
}
