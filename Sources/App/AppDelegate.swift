import Cocoa
import SwiftUI
import ApplicationServices
import CoreGraphics
import Carbon
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var floatingWindows: [NSWindow] = [] // 动态管理的悬浮球窗口数组
    private var noteWindow: NoteWindow?
    private var memoryReviewReminderWindow: MemoryReviewReminderWindow?
    private var memoryReviewDialogWindow: MemoryReviewDialogWindow?
    private var translationPopupWindow: TranslationPopupWindow?
    private var attachedWindow: NSWindow? // 笔记窗口当前依附的悬浮球窗口
    private var attachedButtonIndex: Int? // 笔记窗口当前依附的悬浮球索引
    private var currentNoteMode: NoteListView.ViewMode = .all
    // private var welcomeWindow: WelcomeWindow? // 欢迎窗口（已废弃）
    private var groupDragOrigins: [Int: NSPoint] = [:] // 分组拖拽时记录各成员初始位置
    
    private var globalMonitor: Any?
    private var eventTap: CFMachPort?
    private var hotKeyRef: EventHotKeyRef?
    private var colorPickerHotKeyRef: EventHotKeyRef?
    private var translationHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    // 动态生成位置键
    private func positionKey(for index: Int) -> String {
        return "floatingWindowPosition_\(index)"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hideFromDock()
        setupStatusBar()
        createFloatingWindow()

        // 初始化插件系统
        PluginRegistry.shared.registerBuiltinPlugins()

        // 初始化剪切板管理器，确保在应用启动后立即开始监听并加载剪切板内容
        _ = ClipboardManager.shared

        // 初始化提醒管理器（这将触发智能提醒管理器的启动）
        _ = ReminderManager.shared
        
        // 初始化自动隐藏管理器
        _ = AutoHideManager.shared

        // 初始化记忆功能管理器
        _ = MemoryManager.shared

        // 初始化备份管理器（触发定时备份调度）
        _ = BackupManager.shared



        // 请求系统通知权限（用于非侵入式记忆提示）
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // 自动启动 ACP 服务（如果配置开启且使用 opencode 模式）
        let aiConfig = FloatingButtonConfigManager.shared.config
        if aiConfig.aiMode == .opencode && aiConfig.acpAutoStart {
            Task { @MainActor in
                await AIService.shared.connectACP()
            }
        }

        // 首次启动时打开使用说明
        if AppDatabase.shared.settingsStore.isFirstLaunch() {
            openUserGuide()
            AppDatabase.shared.settingsStore.setFirstLaunchCompleted()
        }

        // 监听配置变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChanged),
            name: GlowFloatingButtonView.configChangedNotification,
            object: nil
        )

        // 监听悬浮球点击通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFloatingButtonClicked),
            name: GlowFloatingButtonView.floatingButtonClickedNotification,
            object: nil
        )

        // 监听删除悬浮球通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeleteFloatingButton),
            name: Notification.Name("deleteFloatingButton"),
            object: nil
        )

        // 监听悬浮球可见性变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisibilityChanged),
            name: GlowFloatingButtonView.visibilityChangedNotification,
            object: nil
        )

        // 监听笔记窗口大小变化以重新对齐
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNoteWindowResized),
            name: NSWindow.didResizeNotification,
            object: nil
        )
        
        // 欢迎窗口已废弃，改为打开使用说明URL
        // NotificationCenter.default.addObserver(
        //     self,
        //     selector: #selector(handleWelcomeWindowDismissed),
        //     name: Notification.Name("WelcomeWindowDismissed"),
        //     object: nil
        // )
        
        // 设置全局快捷键
        setupGlobalHotkey()
        
        // 注册 URL 事件处理
        let em = NSAppleEventManager.shared()
        em.setEventHandler(self, andSelector: #selector(handleGetURL(_:withReply:)),
                           forEventClass: AEEventClass(kInternetEventClass),
                           andEventID: AEEventID(kAEGetURL))

        // 监听悬浮球分组拖拽事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGroupDragStart),
            name: FloatingWindow.dragStartNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGroupDrag),
            name: FloatingWindow.dragNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGroupDragEnd),
            name: FloatingWindow.dragEndNotification,
            object: nil
        )

        // 监听分组成员排列通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArrangeGroupMembers),
            name: Notification.Name("arrangeGroupMembers"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryContextPrompt(_:)),
            name: Notification.Name("MemoryContextPrompt"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryReviewReminder(_:)),
            name: Notification.Name("MemoryReviewReminder"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMemoryReviewDialogNow),
            name: Notification.Name("OpenMemoryReviewDialogNow"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showTranslationPopupWindow),
            name: .showTranslationPopup,
            object: nil
        )



        // 启动时检查权限并引导
        checkPermissionsOnStartup()
    }
    
    private func checkPermissionsOnStartup() {
        let accessibilityGranted = InputMonitor.hasAccessibilityPermission()
        let screenGranted = ScreenRecordingPermission.hasPermission()

        if !accessibilityGranted || !screenGranted {
            Logger.shared.log("⚠️ 启动自检：权限不足，弹出引导窗口")
            PermissionGuideWindow.shared.show()
        } else {
            Logger.shared.log("✅ 启动自检：辅助功能与屏幕录制权限已就绪")
        }
    }

    @objc private func handleMemoryContextPrompt(_ notification: Notification) {
        let message = (notification.userInfo?["message"] as? String) ?? "有相关知识可回顾"
        sendMemoryNotification(title: "记忆提示", body: message)
    }

    @objc private func handleMemoryReviewReminder(_ notification: Notification) {
        let message = (notification.userInfo?["message"] as? String) ?? "有知识到达复习时间"
        sendMemoryNotification(title: "复习提醒", body: message)

        let window = MemoryReviewReminderWindow(message: message)
        window.onStartReview = { [weak self] in
            self?.openMemoryReviewDialog()
        }
        memoryReviewReminderWindow = window
        window.showBottomRight()
    }

    @objc private func handleOpenMemoryReviewDialogNow() {
        openMemoryReviewDialog()
    }

    private func openMemoryReviewDialog() {
        if let existing = memoryReviewDialogWindow {
            let minWidth = MemoryReviewDialogWindow.defaultSize.width
            let minHeight = MemoryReviewDialogWindow.defaultSize.height
            if existing.frame.width < minWidth || existing.frame.height < minHeight {
                let origin = existing.frame.origin
                let target = NSRect(origin: origin, size: NSSize(width: minWidth, height: minHeight))
                existing.setFrame(target, display: true, animate: false)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let dialog = MemoryReviewDialogWindow()
        memoryReviewDialogWindow = dialog
        dialog.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func sendMemoryNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        Logger.shared.log("🌐 收到 URL 打开请求: \(urlString)")
        BrowserPickerWindow.shared.show(for: url)
    }
    
    private func setupGlobalHotkey() {
        removeGlobalHotkey()
        
        Logger.shared.log("开始设置全局快捷键 (Carbon 方式)")

        let config = FloatingButtonConfigManager.shared.config
        let toggleHotkeyString = config.toggleAIXHotkey
        let colorPickerHotkeyString = config.colorPickerHotkey
        let translationHotkeyString = config.translationHotkey

        let toggleParsed = parseHotkeyToCarbon(toggleHotkeyString)
        let colorPickerParsed = parseHotkeyToCarbon(colorPickerHotkeyString)
        let translationParsed = translationHotkeyString.isEmpty ? nil : parseHotkeyToCarbon(translationHotkeyString)

        if toggleParsed == nil && colorPickerParsed == nil && translationParsed == nil {
            Logger.shared.log("快捷键解析失败: \(toggleHotkeyString), \(colorPickerHotkeyString)")
            return
        }
        
        // 1. 设置事件处理器
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let paramStatus = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if paramStatus != noErr {
                return noErr
            }
            
            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1:
                    Logger.shared.log("🔥 全局快捷键触发：切换悬浮球显示状态")
                    appDelegate.toggleFloatingWindow()
                case 2:
                    Logger.shared.log("🎨 全局快捷键触发：启动取色器")
                    appDelegate.startColorPicking()
                case 3:
                    Logger.shared.log("🌐 全局快捷键触发：翻译选中文本")
                    appDelegate.triggerTranslation()
                default:
                    break
                }
            }
            return noErr
        }
        
        let status = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
        
        if status != noErr {
            Logger.shared.log("InstallEventHandler 失败: \(status)")
            return
        }
        
        // 2. 注册热键
        if let (keyCode, carbonModifiers) = toggleParsed {
            Logger.shared.log("快捷键已解析: \(toggleHotkeyString), 键码: \(keyCode), 修饰符: \(carbonModifiers)")
            let hotKeyID = EventHotKeyID(signature: OSType(0x41495821), id: 1)
            let registerStatus = RegisterEventHotKey(
                UInt32(keyCode),
                UInt32(carbonModifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if registerStatus != noErr {
                Logger.shared.log("RegisterEventHotKey 失败: \(registerStatus)")
            }
        } else {
            Logger.shared.log("快捷键解析失败: \(toggleHotkeyString)")
        }

        if let (keyCode, carbonModifiers) = colorPickerParsed {
            Logger.shared.log("快捷键已解析: \(colorPickerHotkeyString), 键码: \(keyCode), 修饰符: \(carbonModifiers)")
            let hotKeyID = EventHotKeyID(signature: OSType(0x41495821), id: 2)
            let registerStatus = RegisterEventHotKey(
                UInt32(keyCode),
                UInt32(carbonModifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &colorPickerHotKeyRef
            )
            if registerStatus != noErr {
                Logger.shared.log("RegisterEventHotKey 失败: \(registerStatus)")
            }
        } else {
            Logger.shared.log("快捷键解析失败: \(colorPickerHotkeyString)")
        }
        
        if let (keyCode, carbonModifiers) = translationParsed {
            Logger.shared.log("快捷键已解析: \(translationHotkeyString), 键码: \(keyCode), 修饰符: \(carbonModifiers)")
            let hotKeyID = EventHotKeyID(signature: OSType(0x41495821), id: 3)
            let registerStatus = RegisterEventHotKey(
                UInt32(keyCode),
                UInt32(carbonModifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &translationHotKeyRef
            )
            if registerStatus != noErr {
                Logger.shared.log("RegisterEventHotKey 失败: \(registerStatus)")
            }
        }

        Logger.shared.log("Carbon 全局快捷键已成功启动")
    }
    
    private func removeGlobalHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let colorPickerHotKeyRef = colorPickerHotKeyRef {
            UnregisterEventHotKey(colorPickerHotKeyRef)
            self.colorPickerHotKeyRef = nil
        }
        if let translationHotKeyRef = translationHotKeyRef {
            UnregisterEventHotKey(translationHotKeyRef)
            self.translationHotKeyRef = nil
        }
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    private func parseHotkeyToCarbon(_ hotkeyString: String) -> (UInt16, Int)? {
        guard let parsed = HotkeyParser.parse(hotkeyString) else {
            return nil
        }
        return (parsed.keyCode, parsed.carbonModifiers)
    }

    private func parseHotkeyToMenuShortcut(_ hotkeyString: String) -> (keyEquivalent: String, modifierMask: NSEvent.ModifierFlags)? {
        let components = hotkeyString.components(separatedBy: "+")
        guard let rawKey = components.last?.trimmingCharacters(in: .whitespacesAndNewlines), !rawKey.isEmpty else {
            return nil
        }

        let keyEquivalent = mapHotkeyKeyEquivalent(rawKey)
        if keyEquivalent.isEmpty {
            return nil
        }

        var modifierMask: NSEvent.ModifierFlags = []
        for component in components.dropLast() {
            let mod = component.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch mod {
            case "cmd", "command":
                modifierMask.insert(.command)
            case "shift":
                modifierMask.insert(.shift)
            case "option", "alt":
                modifierMask.insert(.option)
            case "control", "ctrl":
                modifierMask.insert(.control)
            default:
                break
            }
        }

        return (keyEquivalent: keyEquivalent, modifierMask: modifierMask)
    }

    private func mapHotkeyKeyEquivalent(_ rawKey: String) -> String {
        let normalized = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "SPACE":
            return " "
        case "TAB":
            return "\t"
        case "ENTER", "RETURN":
            return "\r"
        case "ESC", "ESCAPE":
            return "\u{1b}"
        case "DELETE", "BACKSPACE":
            return "\u{8}"
        case "FORWARDDELETE":
            return "\u{7f}"
        default:
            break
        }

        if normalized.count == 1 {
            return normalized.lowercased()
        }

        return ""
    }

    @objc private func handleNoteWindowResized(_ notification: Notification) {
        if let window = notification.object as? NoteWindow, window == noteWindow {
            updateNoteWindowPosition()
        }
    }
    
    // 欢迎窗口已废弃
    // @objc private func handleWelcomeWindowDismissed() {
    //     welcomeWindow?.orderOut(nil)
    //     welcomeWindow = nil
    // }
    
    // private func showWelcomeWindow() { ... }

    @objc private func openUserGuide() {
        if let url = URL(string: "https://space.bilibili.com/25132187") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleDeleteFloatingButton(_ notification: Notification) {
        guard let buttonIndex = notification.object as? Int else {
            return
        }
        performDeleteFloatingButton(index: buttonIndex)
    }

    private func performDeleteFloatingButton(index buttonIndex: Int) {
        let configManager = FloatingButtonConfigManager.shared
        let config = configManager.config

        // 如果只有一个按钮，不允许删除
        if config.buttonCount <= 1 {
            return
        }

        // 1. 关闭指定索引的窗口并在数组中移除
        if buttonIndex < floatingWindows.count {
            let window = floatingWindows[buttonIndex]
            
            // 处理附着的笔记窗口
            if attachedWindow == window {
                noteWindow?.orderOut(nil)
                attachedWindow = nil
                attachedButtonIndex = nil
            }
            
            window.orderOut(nil)
            floatingWindows.remove(at: buttonIndex)
            
            // 更新附着的索引逻辑
            if let currentIdx = attachedButtonIndex {
                if currentIdx == buttonIndex {
                    attachedButtonIndex = nil
                } else if currentIdx > buttonIndex {
                    attachedButtonIndex = currentIdx - 1
                }
            }
        }

        // 2. 重新排列内存中窗口的视图状态
        for i in buttonIndex..<floatingWindows.count {
            if let contentView = floatingWindows[i].contentView as? GlowFloatingButtonView {
                contentView.buttonIndex = i
            }
            floatingWindows[i].title = "悬浮球 \(i + 1)"
        }

        // 3. 更新配置数据 (字典索引迁移)
        var newActions = config.buttonActions
        var newBoundWindows = config.boundWindows
        var newCustomizations = config.buttonCustomizations
        var newCustomIcons = config.customIcons
        var newPluginIds = config.buttonPluginIds
        var newHotkeys = config.buttonHotkeys

        // 移除被删除按钮
        newActions.removeValue(forKey: buttonIndex)
        newBoundWindows.removeValue(forKey: buttonIndex)
        newCustomizations.removeValue(forKey: buttonIndex)
        newCustomIcons.removeValue(forKey: buttonIndex)
        newPluginIds.removeValue(forKey: buttonIndex)
        newHotkeys.removeValue(forKey: buttonIndex)

        // 重排后续索引
        let maxIdx = config.buttonCount - 1
        for i in buttonIndex..<maxIdx {
            if let val = newActions[i + 1] { newActions[i] = val; newActions.removeValue(forKey: i + 1) }
            if let val = newBoundWindows[i + 1] { newBoundWindows[i] = val; newBoundWindows.removeValue(forKey: i + 1) }
            if let val = newCustomizations[i + 1] { newCustomizations[i] = val; newCustomizations.removeValue(forKey: i + 1) }
            if let val = newCustomIcons[i + 1] { newCustomIcons[i] = val; newCustomIcons.removeValue(forKey: i + 1) }
            if let val = newPluginIds[i + 1] { newPluginIds[i] = val; newPluginIds.removeValue(forKey: i + 1) }
            if let val = newHotkeys[i + 1] { newHotkeys[i] = val; newHotkeys.removeValue(forKey: i + 1) }
        }

        // 4. 更新分组信息与隐藏列表 (索引平移)
        var newGroups = config.buttonGroups
        for i in 0..<newGroups.count {
            newGroups[i].memberIndices.removeAll { $0 == buttonIndex }
            newGroups[i].memberIndices = newGroups[i].memberIndices.map { idx in
                return idx > buttonIndex ? idx - 1 : idx
            }
        }
        newGroups.removeAll { $0.memberIndices.isEmpty }

        var newHiddenIndices: [Int] = []
        for idx in config.userHiddenButtonIndices {
            if idx == buttonIndex {
                continue
            } else if idx > buttonIndex {
                newHiddenIndices.append(idx - 1)
            } else {
                newHiddenIndices.append(idx)
            }
        }

        // 5. 应用并保存配置
        configManager.config.buttonCount = max(1, config.buttonCount - 1)
        configManager.config.buttonActions = newActions
        configManager.config.boundWindows = newBoundWindows
        configManager.config.buttonCustomizations = newCustomizations
        configManager.config.customIcons = newCustomIcons
        configManager.config.buttonPluginIds = newPluginIds
        configManager.config.buttonHotkeys = newHotkeys
        configManager.config.buttonGroups = newGroups
        configManager.config.userHiddenButtonIndices = newHiddenIndices
        
        configManager.save()

        // 6. 清理多余的旧位置缓存键
        for i in floatingWindows.count...(config.buttonCount + 5) {
            UserDefaults.standard.removeObject(forKey: positionKey(for: i))
        }

        // 7. 删除后自动顺延重排，消除物理空位
        arrangeFloatingWindows()

        // 8. 发送全局配置变更通知 (确保其他模块感知数据变化)
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)

        // 9. 刷新 UI
        refreshAllWindows()
        showAllFloatingWindows()
        setupStatusBarMenu()
    }

    @objc private func handleVisibilityChanged(_ notification: Notification) {
        setupStatusBarMenu()
    }

    @objc private func handleFloatingButtonClicked(_ notification: Notification) {
        guard let clickedView = notification.object as? GlowFloatingButtonView else {
            Logger.shared.log("❌ handleFloatingButtonClicked: 无法获取 GlowFloatingButtonView")
            return
        }

        let config = FloatingButtonConfigManager.shared.config
        let action = config.buttonActions[clickedView.buttonIndex] ?? .none
        Logger.shared.log("🔵 悬浮球点击: 按钮索引=\(clickedView.buttonIndex), 操作=\(action.rawValue)")

        switch action {
        case .openNote:
            Logger.shared.log("📝 执行打开笔记操作")
            toggleNoteWindow(attachedTo: clickedView.window, buttonIndex: clickedView.buttonIndex, mode: .all)
        case .showClipboard:
            Logger.shared.log("📋 执行剪切板操作")
            toggleNoteWindow(attachedTo: clickedView.window, buttonIndex: clickedView.buttonIndex, mode: .clipboard)
        case .showCompletedNotes:
            Logger.shared.log("✅ 执行已完成笔记操作")
            toggleNoteWindow(attachedTo: clickedView.window, buttonIndex: clickedView.buttonIndex, mode: .completed)
        case .showFavorites:
            Logger.shared.log("📁 执行常用文件操作")
            toggleNoteWindow(attachedTo: clickedView.window, buttonIndex: clickedView.buttonIndex, mode: .favorites)

        case .showKnowledgeList:
            Logger.shared.log("📚 执行知识列表操作")
            toggleNoteWindow(attachedTo: clickedView.window, buttonIndex: clickedView.buttonIndex, mode: .knowledge)
        case .toggleWindow:
            Logger.shared.log("🪟 执行控制窗口操作")
            WindowManager.shared.handleToggleWindow(for: clickedView.buttonIndex)
        case .showReminder:
            Logger.shared.log("🔔 执行提醒休息操作")
            ReminderManager.shared.testReminder()
        case .colorList:
            Logger.shared.log("🎨 执行颜色列表操作")
            if let ballWindow = clickedView.window {
                if ColorListWindow.shared.isVisible {
                    ColorListWindow.shared.orderOut(nil)
                } else {
                    ColorListWindow.shared.show(near: ballWindow.frame)
                }
            }
        case .executeHotkey:
            let hotkey = config.buttonHotkeys[clickedView.buttonIndex] ?? ""
            guard !hotkey.isEmpty else {
                Logger.shared.log("⚠️ 未绑定快捷键")
                return
            }
            if !InputMonitor.hasAccessibilityPermission() {
                Logger.shared.log("⚠️ 缺少辅助功能权限，无法执行快捷键")
                return
            }
            Logger.shared.log("⌨️ 执行快捷键: \(hotkey)")
            if !HotkeyExecutor.execute(hotkey: hotkey) {
                Logger.shared.log("❌ 快捷键执行失败")
            }
        case .plugin:
            Logger.shared.log("🔌 执行插件操作")
            if let pluginId = config.buttonPluginIds[clickedView.buttonIndex] {
                let context = PluginContext(
                    sender: clickedView,
                    window: clickedView.window,
                    userInfo: ["buttonIndex": clickedView.buttonIndex]
                )
                do {
                    try PluginManager.shared.execute(pluginId: pluginId, context: context)
                } catch {
                    Logger.shared.log("❌ 插件执行失败: \(error.localizedDescription)")
                }
            } else {
                Logger.shared.log("⚠️ 未配置插件ID")
            }
        case .none:
            Logger.shared.log("⚠️ 无操作")
            break
        }
    }



    private func toggleNoteWindow(attachedTo window: NSWindow?, buttonIndex: Int, mode: NoteListView.ViewMode = .all) {
        if let noteWin = noteWindow, noteWin.isVisible {
            if attachedWindow == window && currentNoteMode == mode {
                // 如果点击的是同一个悬浮球，且模式相同，则隐藏
                noteWin.orderOut(nil)
                return
            }
            
            // 否则更新模式和依附窗口
            currentNoteMode = mode
            attachedWindow = window
            attachedButtonIndex = buttonIndex
            noteWin.setMode(mode)
        } else {
            // 窗口未显示，创建或显示
            currentNoteMode = mode
            attachedWindow = window
            attachedButtonIndex = buttonIndex
            if noteWindow == nil {
                noteWindow = NoteWindow(initialViewMode: mode)
            } else {
                noteWindow?.setMode(mode)
            }
        }
        
        noteWindow?.updateHeightToFit()
        updateNoteWindowPosition()
        
        // 使用 orderFrontRegardless 强制显示窗口
        guard let noteWin = noteWindow else { return }
        noteWin.orderFrontRegardless()
        
        // 面板打开，保持其他悬浮球显示

        
        // 延迟激活确保窗口布局完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // 确保应用激活
            NSApp.activate(ignoringOtherApps: true)
            // 确保窗口成为 key window
            noteWin.makeKey()
        }
    }

    /// 隐藏同分组的其他悬浮球
    private func hideGroupFloatingWindows(for index: Int, except window: NSWindow?) {
        let configManager = FloatingButtonConfigManager.shared
        // 获取当前按钮所属分组的所有成员索引
        let groupMembers = configManager.getGroup(for: index)?.memberIndices ?? [index]
        
        for (idx, w) in floatingWindows.enumerated() {
            if groupMembers.contains(idx) && w !== window {
                w.orderOut(nil)
            }
        }
    }

    /// 显示同分组的所有悬浮球
    private func showGroupFloatingWindows(for index: Int) {
        let configManager = FloatingButtonConfigManager.shared
        let config = configManager.config
        let groupMembers = configManager.getGroup(for: index)?.memberIndices ?? [index]
        
        for idx in groupMembers {
            if idx < floatingWindows.count && idx < config.buttonCount {
                floatingWindows[idx].orderFrontRegardless()
            }
        }
    }

    /// 隐藏除指定窗口外的其他悬浮球
    private func hideOtherFloatingWindows(except window: NSWindow?) {
        for w in floatingWindows where w !== window {
            w.orderOut(nil)
        }
    }

    /// 显示所有悬浮球
    private func showAllFloatingWindows() {
        let config = FloatingButtonConfigManager.shared.config
        for (index, window) in floatingWindows.enumerated() {
            if index < config.buttonCount {
                window.orderFrontRegardless()
            }
        }
    }

    private func updateNoteWindowPosition() {
        guard let targetWindow = attachedWindow, let noteWin = noteWindow else { return }

        let frame1 = targetWindow.frame
        let noteFrame = noteWin.frame
        let screenFrame = targetWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // 获取按钮的实际尺寸和位置
        let configManager = FloatingButtonConfigManager.shared
        let buttonIndex = floatingWindows.firstIndex(of: targetWindow) ?? 0
        let buttonSize = configManager.getButtonSize(index: buttonIndex)
        let shape = configManager.getButtonShape(index: buttonIndex)

        // 根据形状计算按钮的实际宽度和高度
        let buttonWidth: CGFloat
        let buttonHeight: CGFloat
        switch shape {
        case .circle, .roundedSquare:
            buttonWidth = buttonSize
            buttonHeight = buttonSize
        case .capsule:
            buttonWidth = max(buttonSize, buttonSize * 1.4)
            buttonHeight = max(18.0, buttonSize * 0.6)
        }

        // 按钮在窗口中居中，计算按钮的实际边缘位置
        let buttonLeft = frame1.midX - buttonWidth / 2
        let buttonRight = frame1.midX + buttonWidth / 2

        // 悬浮球的可见区域（用于防遮盖检测）
        let ballRect = CGRect(
            x: frame1.midX - buttonWidth / 2,
            y: frame1.midY - buttonHeight / 2,
            width: buttonWidth,
            height: buttonHeight
        )

        // 优先尝试在右侧显示
        var newX = buttonRight

        // 检查右侧空间是否足够
        if newX + noteFrame.width > screenFrame.maxX {
            // 右侧空间不足，改在左侧显示
            // 添加向右110像素的偏移量，使窗口更靠近悬浮球
            newX = buttonLeft - noteFrame.width + 110
        }

        // 确保不会超出屏幕左边缘
        newX = max(newX, screenFrame.minX)

        // Y 轴对齐：居中对齐
        // 悬浮按钮的中心 Y 坐标
        let buttonCenterY = frame1.midY
        // 笔记窗口的起始 Y 坐标 = 按钮中心 Y - 窗口高度的一半
        var newY = buttonCenterY - noteFrame.height / 2

        // 确保窗口不会超出屏幕顶部或底部
        newY = max(newY, screenFrame.minY)
        newY = min(newY, screenFrame.maxY - noteFrame.height)

        // 防遮盖检测：检查面板是否遮盖悬浮球，若遮盖则挤开面板
        let gap: CGFloat = 4 // 面板与悬浮球之间的最小间距
        let noteRect = CGRect(x: newX, y: newY, width: noteFrame.width, height: noteFrame.height)
        if ballRect.intersects(noteRect) {
            // 判断面板主体在悬浮球左侧还是右侧
            if noteRect.midX < ballRect.midX {
                // 面板在左侧，向左挤开
                newX = ballRect.minX - noteFrame.width - gap
            } else {
                // 面板在右侧，向右挤开
                newX = ballRect.maxX + gap
            }
            // 再次确保不超出屏幕边缘
            newX = max(newX, screenFrame.minX)
            if newX + noteFrame.width > screenFrame.maxX {
                newX = screenFrame.maxX - noteFrame.width
            }
        }

        noteWin.setFrameOrigin(NSPoint(x: newX, y: newY))

        // 确保笔记窗口在悬浮按钮之上，以便笔记窗口右侧的功能按钮可以正常点击
        noteWin.level = .popUpMenu
    }

    @objc private func handleConfigChanged(_ notification: Notification) {
        refreshAllWindows()
        setupGlobalHotkey()
    }

    private func refreshAllWindows() {
        let config = FloatingButtonConfigManager.shared.config
        let currentCount = floatingWindows.count
        let targetCount = config.buttonCount

        // 如果需要增加窗口
        if targetCount > currentCount {
            for index in currentCount..<targetCount {
                createFloatingWindow(at: index)
            }
        }
        
        // 如果需要减少窗口
        else if targetCount < currentCount {
            for index in (targetCount..<currentCount).reversed() {
                if index < floatingWindows.count {
                    let window = floatingWindows[index]
                    // 如果笔记窗口依附于要删除的窗口，则隐藏笔记窗口
                    if attachedWindow == window {
                        noteWindow?.orderOut(nil)
                        attachedWindow = nil
                    }
                    window.orderOut(nil)
                    floatingWindows.remove(at: index)
                }
            }
        }

        // 刷新现有窗口
        for (index, window) in floatingWindows.enumerated() {
            if let contentView = window.contentView as? GlowFloatingButtonView {
                contentView.refreshConfig()
            } else if let contentView = window.contentView as? FloatingButtonView {
                contentView.refreshConfig()
            }
            
            if let floatingWindow = window as? FloatingWindow {
                let size = FloatingButtonConfigManager.shared.getButtonSize(index: index)
                floatingWindow.updateSize(size)
            }
            
            // 确保窗口遵从全局隐藏与用户隐藏状态
            if index < config.buttonCount {
                let isGlobalHidden = FloatingButtonConfigManager.shared.getGlobalHiddenState()
                let isUserHidden = FloatingButtonConfigManager.shared.isButtonHiddenByUser(index: index)
                if !isGlobalHidden && !isUserHidden {
                    window.orderFrontRegardless()
                } else {
                    window.orderOut(nil)
                }
            }
        }

        // 如果依附的窗口被隐藏了，则隐藏笔记窗口
        if let attached = attachedWindow, !attached.isVisible {
            noteWindow?.orderOut(nil)
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 创建自定义菜单栏视图
        if let button = statusItem?.button {
            let timerView = StatusBarTimerView()
            timerView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(timerView)
            
            NSLayoutConstraint.activate([
                timerView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: timerView.trailingAnchor),
                timerView.topAnchor.constraint(equalTo: button.topAnchor),
                timerView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
        }

        setupStatusBarMenu()
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        print("菜单栏按钮被点击")
        toggleFloatingWindow()
    }

    private func setupStatusBarMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem.separator())

        // 悬浮球操作子菜单
        menu.addItem(NSMenuItem.separator())
        let actionsMenu = NSMenuItem(title: L10n.tr("menu.floatingButtonActions"), action: nil, keyEquivalent: "")
        let actionsSubMenu = NSMenu()

        let config = FloatingButtonConfigManager.shared.config
        for i in 0..<config.buttonCount {
            let buttonItem = NSMenuItem(title: L10n.tr("menu.button", i + 1), action: nil, keyEquivalent: "")
            let buttonSubMenu = NSMenu()

            for action in FloatingButtonConfig.ButtonAction.allCases where action != .plugin && action != .showReminder {
                // 如果是控制窗口模式，且没有辅助功能权限，则不显示该选项
                if action == .toggleWindow && !InputMonitor.hasAccessibilityPermission() {
                    continue
                }
                
                let actionItem = NSMenuItem(title: action.localizedName, action: #selector(actionItemClicked(_:)), keyEquivalent: "")
                actionItem.target = self
                actionItem.state = (config.buttonActions[i] == action) ? .on : .off
                actionItem.tag = i * 100 + FloatingButtonConfig.ButtonAction.allCases.firstIndex(of: action)!
                buttonSubMenu.addItem(actionItem)
            }

            // 如果当前是控制窗口模式且已授权，添加清除绑定选项
            if config.buttonActions[i] == .toggleWindow && InputMonitor.hasAccessibilityPermission() {
                buttonSubMenu.addItem(NSMenuItem.separator())
                let clearItem = NSMenuItem(title: L10n.tr("menu.rebindWindow"), action: #selector(clearWindowBindingFromMenu(_:)), keyEquivalent: "")
                clearItem.target = self
                clearItem.tag = i
                buttonSubMenu.addItem(clearItem)
            }

            // 添加删除选项
            buttonSubMenu.addItem(NSMenuItem.separator())

            // 如果只剩一个按钮，不显示删除选项
            if config.buttonCount > 1 {
                let deleteItem = NSMenuItem(title: L10n.tr("menu.deleteButton"), action: #selector(deleteFloatingButton(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.tag = i
                buttonSubMenu.addItem(deleteItem)
            }

            // 悬浮球显隐切换选项
            if i < floatingWindows.count {
                if floatingWindows[i].isVisible {
                    let hideItem = NSMenuItem(title: L10n.tr("common.hide"), action: #selector(hideFloatingButton(_:)), keyEquivalent: "")
                    hideItem.target = self
                    hideItem.tag = i
                    buttonSubMenu.addItem(hideItem)
                } else {
                    let showItem = NSMenuItem(title: L10n.tr("menu.restoreButton"), action: #selector(showFloatingButton(_:)), keyEquivalent: "")
                    showItem.target = self
                    showItem.tag = i
                    buttonSubMenu.addItem(showItem)
                }
            }

            buttonItem.submenu = buttonSubMenu
            actionsSubMenu.addItem(buttonItem)
        }
        actionsMenu.submenu = actionsSubMenu
        menu.addItem(actionsMenu)

        menu.addItem(NSMenuItem.separator())

        let isGlobalHidden = FloatingButtonConfigManager.shared.getGlobalHiddenState()
        let toggleTitle = isGlobalHidden ? L10n.tr("menu.show") : L10n.tr("menu.hide")
        let toggleAllItem = NSMenuItem(title: toggleTitle, action: #selector(toggleFloatingWindow), keyEquivalent: "")
        toggleAllItem.target = self
        // 对标题进行转义，因为系统设置中可能需要完全匹配
        // 系统快捷键会通过菜单标题来查找项目
        menu.addItem(toggleAllItem)

        let addButtonItem = NSMenuItem(title: L10n.tr("menu.addButton"), action: #selector(addFloatingButton), keyEquivalent: "")
        addButtonItem.target = self
        // 达到上限时禁用
        if FloatingButtonConfigManager.shared.config.buttonCount >= 10 {
            addButtonItem.isEnabled = false
        }
        menu.addItem(addButtonItem)

        let arrangeItem = NSMenuItem(title: L10n.tr("menu.globalArrange"), action: #selector(arrangeFloatingWindows), keyEquivalent: "")
        arrangeItem.target = self
        menu.addItem(arrangeItem)

        let officialInitItem = NSMenuItem(title: L10n.tr("menu.officialInit"), action: #selector(officialInit), keyEquivalent: "")
        officialInitItem.target = self
        menu.addItem(officialInitItem)

        menu.addItem(NSMenuItem.separator())



        let colorPickerItem = NSMenuItem(title: L10n.tr("menu.colorPicker"), action: #selector(startColorPicking), keyEquivalent: "")
        if let parsed = parseHotkeyToMenuShortcut(FloatingButtonConfigManager.shared.config.colorPickerHotkey) {
            colorPickerItem.keyEquivalent = parsed.keyEquivalent
            colorPickerItem.keyEquivalentModifierMask = parsed.modifierMask
        } else {
            colorPickerItem.keyEquivalent = ""
            colorPickerItem.keyEquivalentModifierMask = []
        }
        colorPickerItem.target = self
        menu.addItem(colorPickerItem)



        menu.addItem(NSMenuItem.separator())

        let welcomeItem = NSMenuItem(title: L10n.tr("menu.userGuide"), action: #selector(openUserGuide), keyEquivalent: "")
        welcomeItem.target = self
        menu.addItem(welcomeItem)

        let settingsItem = NSMenuItem(title: L10n.tr("menu.preferences"), action: #selector(showSettingsPanel), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.image = nil
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: L10n.tr("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func showTranslationPopupWindow() {
        if translationPopupWindow == nil {
            translationPopupWindow = TranslationPopupWindow()
        }
        translationPopupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func triggerTranslation() {
        TranslationManager.shared.triggerTranslation()
    }

    @objc private func colorItemClicked(_ sender: NSMenuItem) {
        guard let schemeName = sender.representedObject as? String,
              let scheme = FloatingButtonConfig.ColorScheme(rawValue: schemeName) else {
            return
        }

        FloatingButtonConfigManager.shared.updateColorScheme(scheme)

        // 刷新按钮视图
        refreshAllWindows()

        // 重建菜单以更新状态
        setupStatusBarMenu()
    }

    @objc private func countItemClicked(_ sender: NSMenuItem) {
        let newCount = sender.tag
        FloatingButtonConfigManager.shared.updateButtonCount(newCount)

        // 刷新按钮视图
        refreshAllWindows()

        // 重建菜单以更新状态
        setupStatusBarMenu()
    }

    @objc private func clearWindowBindingFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        FloatingButtonConfigManager.shared.unbindWindow(index: index)
        
        // 立即进入窗口选择蒙版
        WindowManager.shared.startWindowSelection(for: index)
        
        // 刷新按钮视图
        refreshAllWindows()
        
        // 重建菜单以更新状态
        setupStatusBarMenu()
    }

    @objc private func actionItemClicked(_ sender: NSMenuItem) {
        let buttonIndex = sender.tag / 100
        let actionIndex = sender.tag % 100
        let action = FloatingButtonConfig.ButtonAction.allCases[actionIndex]
        
        FloatingButtonConfigManager.shared.updateButtonAction(index: buttonIndex, action: action)
        
        // 刷新按钮视图
        refreshAllWindows()
        
        // 重建菜单以更新状态
        setupStatusBarMenu()
    }

    private func createFloatingWindow() {
        let config = FloatingButtonConfigManager.shared.config
        
        // 根据配置创建所有悬浮球
        for index in 0..<config.buttonCount {
            createFloatingWindow(at: index)
        }
    }
    
    private func createFloatingWindow(at index: Int) {
        let config = FloatingButtonConfigManager.shared.config
        let configManager = FloatingButtonConfigManager.shared
        
        // 创建悬浮球视图
        let contentView = GlowFloatingButtonView()
        contentView.buttonIndex = index
        let window = FloatingWindow(contentView: contentView)
        // 调整窗口尺寸以匹配当前按钮形状（避免容器仍为正方形而导致裁切）
        let baseSize = configManager.getButtonSize(index: index)
        window.updateSize(baseSize)
        
        // 设置窗口初始位置
        if let savedPosition = loadSavedPosition(key: positionKey(for: index)) {
            window.setFrameOrigin(savedPosition)
        } else {
            // 如果没有保存的位置，设置默认位置
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowSize = window.frame.size
                let buttonDiameter = FloatingButtonConfigManager.shared.getButtonSize(index: index)
                
                // 在屏幕右半边顶部居中排列，间距为按钮直径的 0.1 倍
                let spacing = buttonDiameter * 0.1
                let totalWidth = CGFloat(config.buttonCount) * windowSize.width + CGFloat(config.buttonCount - 1) * spacing
                let rightHalfCenterX = screenFrame.midX + screenFrame.width / 4
                let startX = rightHalfCenterX - totalWidth / 2
                let topY = screenFrame.maxY - windowSize.height
                let posX = startX + CGFloat(index) * (windowSize.width + spacing)
                
                window.setFrameOrigin(NSPoint(x: posX, y: topY))
            }
        }
        
        // 检查窗口是否应该显示或隐藏
        let isUserHidden = configManager.isButtonHiddenByUser(index: index)
        let isGlobalHidden = configManager.getGlobalHiddenState()
        
        if !isUserHidden && !isGlobalHidden {
            // 只有窗口既未被用户隐藏也未被全局隐藏时才显示
            window.orderFrontRegardless()
            window.makeKey()
        }
        
        // 添加到数组
        floatingWindows.append(window)
        
        // 监听窗口移动事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
    }

    private func loadSavedPosition(key: String) -> NSPoint? {
        if let data = UserDefaults.standard.data(forKey: key),
           let point = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data) {
            return point.pointValue
        }
        return nil
    }

    private func savePosition(_ position: NSPoint, key: String) {
        let pointValue = NSValue(point: position)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: pointValue, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // 查找窗口在数组中的索引
        if let index = floatingWindows.firstIndex(where: { $0 == window }) {
            savePosition(window.frame.origin, key: positionKey(for: index))
            
            // 笔记窗口跟随移动
            if noteWindow?.isVisible == true && attachedWindow == window {
                updateNoteWindowPosition()
            }
        }
    }

    // MARK: - 悬浮球分组拖拽

    @objc private func handleGroupDragStart(_ notification: Notification) {
        guard let draggedWindow = notification.object as? NSWindow,
              let draggedIndex = floatingWindows.firstIndex(of: draggedWindow) else { return }
        
        let configManager = FloatingButtonConfigManager.shared
        guard let group = configManager.getGroup(for: draggedIndex) else { return }
        
        // 记录同组所有成员的初始位置
        groupDragOrigins.removeAll()
        for memberIndex in group.memberIndices {
            if memberIndex < floatingWindows.count {
                groupDragOrigins[memberIndex] = floatingWindows[memberIndex].frame.origin
            }
        }
    }

    @objc private func handleGroupDrag(_ notification: Notification) {
        guard let draggedWindow = notification.object as? NSWindow,
              let userInfo = notification.userInfo,
              let deltaX = userInfo["deltaX"] as? CGFloat,
              let deltaY = userInfo["deltaY"] as? CGFloat,
              let draggedIndex = floatingWindows.firstIndex(of: draggedWindow) else { return }
        
        let configManager = FloatingButtonConfigManager.shared
        guard let group = configManager.getGroup(for: draggedIndex) else { return }
        
        // 移动同组其他成员
        for memberIndex in group.memberIndices where memberIndex != draggedIndex {
            guard memberIndex < floatingWindows.count,
                  let originalOrigin = groupDragOrigins[memberIndex] else { continue }
            let newOrigin = NSPoint(x: originalOrigin.x + deltaX, y: originalOrigin.y + deltaY)
            floatingWindows[memberIndex].setFrameOrigin(newOrigin)
        }
    }

    @objc private func handleGroupDragEnd(_ notification: Notification) {
        guard let draggedWindow = notification.object as? NSWindow,
              let draggedIndex = floatingWindows.firstIndex(of: draggedWindow) else {
            groupDragOrigins.removeAll()
            return
        }
        
        let configManager = FloatingButtonConfigManager.shared
        if let group = configManager.getGroup(for: draggedIndex) {
            // 保存同组所有成员位置
            for memberIndex in group.memberIndices {
                if memberIndex < floatingWindows.count {
                    savePosition(floatingWindows[memberIndex].frame.origin, key: positionKey(for: memberIndex))
                }
            }
        }
        groupDragOrigins.removeAll()
    }

    /// 当分组成员变化时，按分组设置排列成员
    @objc private func handleArrangeGroupMembers(_ notification: Notification) {
        guard let buttonIndex = notification.object as? Int else {
            Logger.shared.log("⚠️ handleArrangeGroupMembers: invalid notification object")
            return
        }
        let configManager = FloatingButtonConfigManager.shared
        guard let group = configManager.getGroup(for: buttonIndex) else {
            Logger.shared.log("⚠️ handleArrangeGroupMembers: no group for button \(buttonIndex)")
            return
        }
        guard group.memberIndices.count > 1 else {
            Logger.shared.log("⚠️ handleArrangeGroupMembers: group \(group.name) only has \(group.memberIndices.count) member(s)")
            return
        }
        
        Logger.shared.log("📐 arrangeGroupMembers: group=\(group.name), members=\(group.memberIndices), layout=\(group.layout.rawValue)")

        // 过滤并仅保留有效的窗口索引
        let validMemberIndices = group.memberIndices.filter { $0 < floatingWindows.count }
        if validMemberIndices.isEmpty { return }
        
        // 重要：在排列前，先确保所有分组成员的窗口尺寸已根据最新配置更新
        for mId in validMemberIndices {
            let size = configManager.getButtonSize(index: mId)
            if let floatingWin = floatingWindows[mId] as? FloatingWindow {
                floatingWin.updateSize(size)
            }
        }

        // 统一间距，确保分组成员均匀排列
        let spacing: CGFloat = -10
        
        // 获取主屏幕用于边界检查
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero

        // 以第一个成员为基准排列
        let firstIndex = validMemberIndices[0]
        let baseOrigin = floatingWindows[firstIndex].frame.origin
        
        // 使用变量记录上一个成功放置成员的位置和大小，以支持跨过无效索引的连续排列
        var lastOrigin = baseOrigin
        var lastSize = floatingWindows[firstIndex].frame.size

        for (offset, memberIndex) in validMemberIndices.enumerated() {
            let memberWindow = floatingWindows[memberIndex]
            let memberSize = memberWindow.frame.size

            var newOrigin: NSPoint
            if offset == 0 {
                newOrigin = baseOrigin
            } else {
                switch group.layout {
                case .horizontal:
                    newOrigin = NSPoint(x: lastOrigin.x + lastSize.width + spacing, y: baseOrigin.y)
                case .vertical:
                    // 垂直排列
                    newOrigin = NSPoint(x: baseOrigin.x, y: lastOrigin.y - memberSize.height - spacing)
                }
            }
            
            // 越界纠正（防止球飞出屏幕不可见）
            if !screenFrame.isEmpty {
                newOrigin.x = max(screenFrame.minX, min(newOrigin.x, screenFrame.maxX - memberSize.width))
                newOrigin.y = max(screenFrame.minY, min(newOrigin.y, screenFrame.maxY - memberSize.height))
            }

            memberWindow.setFrameOrigin(newOrigin)
            savePosition(newOrigin, key: positionKey(for: memberIndex))
            
            // 更新最后放置位置用于下一次循环
            lastOrigin = newOrigin
            lastSize = memberSize
        }
    }

    private func hideFromDock() {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func toggleFloatingWindow() {
        let configManager = FloatingButtonConfigManager.shared
        let config = configManager.config
        
        // 获取所有"未被用户隐藏"的悬浮球
        let visibleByUserIndices = (0..<config.buttonCount).filter { !configManager.isButtonHiddenByUser(index: $0) }
        
        // 检查这些未被隐藏的悬浮球是否全部可见
        let allVisibleButtonsAreShown = !visibleByUserIndices.isEmpty && visibleByUserIndices.allSatisfy { index in
            index < floatingWindows.count && floatingWindows[index].isVisible
        }
        
        if allVisibleButtonsAreShown {
            // 隐藏所有未被用户隐藏的悬浮球
            noteWindow?.orderOut(nil)
            for index in visibleByUserIndices {
                if index < floatingWindows.count {
                    floatingWindows[index].orderOut(nil)
                }
            }
            configManager.setGlobalHiddenState(true)
        } else {
            // 显示所有未被用户隐藏的悬浮球
            for index in visibleByUserIndices {
                if index < floatingWindows.count {
                    floatingWindows[index].orderFrontRegardless()
                    floatingWindows[index].makeKey()
                }
            }
            configManager.setGlobalHiddenState(false)
        }

        setupStatusBarMenu()
    }

    @objc private func showFloatingButton(_ sender: NSMenuItem) {
        let buttonIndex = sender.tag
        if buttonIndex < floatingWindows.count {
            // 从用户隐藏列表中移除
            FloatingButtonConfigManager.shared.removeUserHiddenButton(index: buttonIndex)
            if FloatingButtonConfigManager.shared.getGlobalHiddenState() {
                FloatingButtonConfigManager.shared.setGlobalHiddenState(false)
            }
            let window = floatingWindows[buttonIndex]
            window.orderFrontRegardless()
            window.makeKey()
            setupStatusBarMenu()
            NotificationCenter.default.post(name: GlowFloatingButtonView.visibilityChangedNotification, object: nil)
        }
    }

    @objc private func hideFloatingButton(_ sender: NSMenuItem) {
        let buttonIndex = sender.tag
        if buttonIndex < floatingWindows.count {
            FloatingButtonConfigManager.shared.recordUserHiddenButton(index: buttonIndex)
            let window = floatingWindows[buttonIndex]
            if attachedWindow == window {
                noteWindow?.orderOut(nil)
                attachedWindow = nil
                attachedButtonIndex = nil
            }
            window.orderOut(nil)
            setupStatusBarMenu()
            NotificationCenter.default.post(name: GlowFloatingButtonView.visibilityChangedNotification, object: nil)
        }
    }

    @MainActor @objc private func showSettingsPanel() {
        SettingsWindowManager.shared.showSettings()
    }

    @objc private func arrangeFloatingWindows() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let configManager = FloatingButtonConfigManager.shared
        let config = configManager.config
        let count = min(floatingWindows.count, config.buttonCount)
        guard count > 0 else { return }

        // 如果只有1个悬浮球，直接保存并返回
        if count == 1 {
            let window = floatingWindows[0]
            savePosition(window.frame.origin, key: positionKey(for: 0))
            return
        }

        struct WindowItem {
            let index: Int
            let origin: NSPoint
            let size: CGSize
        }

        var items: [WindowItem] = []
        for i in 0..<count {
            let window = floatingWindows[i]
            items.append(WindowItem(index: i, origin: window.frame.origin, size: window.frame.size))
        }

        let minX = items.map { $0.origin.x }.min() ?? 0
        let maxX = items.map { $0.origin.x }.max() ?? 0
        let minY = items.map { $0.origin.y }.min() ?? 0
        let maxY = items.map { $0.origin.y }.max() ?? 0

        let spanX = maxX - minX
        let spanY = maxY - minY

        // 统一间距：与分组排列保持一致 (-10)
        let spacing: CGFloat = -10

        if spanY > spanX {
            // 纵向走向：从上到下排列 (macOS 坐标系下，Y 越大越靠近屏幕顶部)
            // 排序规则：Y 降序（自顶向底），若 Y 相近则 X 升序
            let sorted = items.sorted { item1, item2 in
                if abs(item1.origin.y - item2.origin.y) > 1 {
                    return item1.origin.y > item2.origin.y
                }
                return item1.origin.x < item2.origin.x
            }

            let baseItem = sorted[0]
            let baseOrigin = baseItem.origin
            var lastOrigin = baseOrigin

            var targetPositions: [(index: Int, origin: NSPoint, size: CGSize)] = []

            for (offset, item) in sorted.enumerated() {
                var newOrigin: NSPoint
                if offset == 0 {
                    newOrigin = baseOrigin
                } else {
                    // 垂直向下排列 (Y 减少)
                    newOrigin = NSPoint(x: baseOrigin.x, y: lastOrigin.y - item.size.height - spacing)
                }
                targetPositions.append((index: item.index, origin: newOrigin, size: item.size))
                lastOrigin = newOrigin
            }

            // 越界安全防护（若底部超出屏幕可视区域底端，整体向上平移）
            let lowestY = targetPositions.map { $0.origin.y }.min() ?? screenFrame.minY
            var offsetY: CGFloat = 0
            if lowestY < screenFrame.minY {
                offsetY = screenFrame.minY - lowestY
            }

            // 若平移后顶部超出屏幕顶端，限制在顶端
            let highestItem = targetPositions[0]
            if highestItem.origin.y + highestItem.size.height + offsetY > screenFrame.maxY {
                offsetY = screenFrame.maxY - (highestItem.origin.y + highestItem.size.height)
            }

            for target in targetPositions {
                let window = floatingWindows[target.index]
                var finalOrigin = NSPoint(x: target.origin.x, y: target.origin.y + offsetY)
                // 确保在屏幕可视区域内
                finalOrigin.x = max(screenFrame.minX, min(finalOrigin.x, screenFrame.maxX - target.size.width))
                finalOrigin.y = max(screenFrame.minY, min(finalOrigin.y, screenFrame.maxY - target.size.height))
                window.setFrameOrigin(finalOrigin)
                savePosition(finalOrigin, key: positionKey(for: target.index))
            }

        } else {
            // 横向走向：从左到右排列 (macOS 坐标系下，X 越小越靠近屏幕左侧)
            // 排序规则：X 升序（自左向右），若 X 相近则 Y 降序
            let sorted = items.sorted { item1, item2 in
                if abs(item1.origin.x - item2.origin.x) > 1 {
                    return item1.origin.x < item2.origin.x
                }
                return item1.origin.y > item2.origin.y
            }

            let baseItem = sorted[0]
            let baseOrigin = baseItem.origin
            var lastOrigin = baseOrigin
            var lastSize = baseItem.size

            var targetPositions: [(index: Int, origin: NSPoint, size: CGSize)] = []

            for (offset, item) in sorted.enumerated() {
                var newOrigin: NSPoint
                if offset == 0 {
                    newOrigin = baseOrigin
                } else {
                    // 水平向右排列 (X 增加)
                    newOrigin = NSPoint(x: lastOrigin.x + lastSize.width + spacing, y: baseOrigin.y)
                }
                targetPositions.append((index: item.index, origin: newOrigin, size: item.size))
                lastOrigin = newOrigin
                lastSize = item.size
            }

            // 越界安全防护（若右侧超出屏幕可视区域右端，整体向左平移）
            let rightmostX = targetPositions.map { $0.origin.x + $0.size.width }.max() ?? screenFrame.maxX
            var offsetX: CGFloat = 0
            if rightmostX > screenFrame.maxX {
                offsetX = screenFrame.maxX - rightmostX
            }

            // 若平移后左侧超出屏幕左端，限制在左端
            let leftmostX = targetPositions[0].origin.x + offsetX
            if leftmostX < screenFrame.minX {
                offsetX += (screenFrame.minX - leftmostX)
            }

            for target in targetPositions {
                let window = floatingWindows[target.index]
                var finalOrigin = NSPoint(x: target.origin.x + offsetX, y: target.origin.y)
                // 确保在屏幕可视区域内
                finalOrigin.x = max(screenFrame.minX, min(finalOrigin.x, screenFrame.maxX - target.size.width))
                finalOrigin.y = max(screenFrame.minY, min(finalOrigin.y, screenFrame.maxY - target.size.height))
                window.setFrameOrigin(finalOrigin)
                savePosition(finalOrigin, key: positionKey(for: target.index))
            }
        }
    }

    @objc private func addFloatingButton() {
        let config = FloatingButtonConfigManager.shared.config
        let newCount = config.buttonCount + 1 // 移除数量限制
        FloatingButtonConfigManager.shared.updateButtonCount(newCount)

        // 刷新按钮视图
        refreshAllWindows()

        // 重建菜单以更新状态
        setupStatusBarMenu()
    }

    @objc private func officialInit() {
        let configManager = FloatingButtonConfigManager.shared
        let currentCount = configManager.config.buttonCount

        // 检查是否超过上限
        let addCount = min(3, 10 - currentCount)
        guard addCount > 0 else {
            Logger.shared.log("⚠️ 悬浮球已达上限(10)，无法添加官方初始化球")
            return
        }

        let startIndex = currentCount

        // 添加悬浮球
        configManager.updateButtonCount(currentCount + addCount)

        // 设置默认动作
        let allActions: [FloatingButtonConfig.ButtonAction] = [.openNote, .showClipboard, .showFavorites]
        for i in 0..<addCount {
            configManager.config.buttonActions[startIndex + i] = allActions[i]
        }

        // 设置默认颜色
        let allColors: [FloatingButtonConfig.ColorScheme] = [.sunsetOrange, .forestGreen, .oceanBlue]
        for i in 0..<addCount {
            configManager.config.buttonCustomizations[startIndex + i] = FloatingButtonConfig.ButtonCustomization(colorScheme: allColors[i])
        }

        configManager.save()

        // 刷新窗口和菜单
        refreshAllWindows()
        setupStatusBarMenu()
    }

    @objc private func startColorPicking() {
        ColorPickerManager.shared.startPicking()
    }

    @objc private func deleteFloatingButton(_ sender: NSMenuItem) {
        let buttonIndex = sender.tag
        performDeleteFloatingButton(index: buttonIndex)
    }

    @MainActor @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 保存应用退出时间
        let exitTime = Date().timeIntervalSince1970
        let exitTimeString = String(exitTime)
        try? AppDatabase.shared.settingsStore.saveConfig(key: "appExitTime", value: exitTimeString)
        print("💾 已保存应用退出时间: \(exitTimeString)")
    }
}
