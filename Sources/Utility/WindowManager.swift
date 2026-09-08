import Cocoa
import ApplicationServices
import CoreGraphics

@MainActor
class WindowManager {
    static let shared = WindowManager()
    
    private var selectorWindow: NSWindow?
    private var selectingForIndex: Int?
    
    private init() {}
    
    // MARK: - 窗口选择
    
    func startWindowSelection(for buttonIndex: Int) {
        if !InputMonitor.hasAccessibilityPermission() {
            requestAccessibilityPermission()
            return
        }
        
        Logger.shared.log("🎯 开始窗口选择: buttonIndex=\(buttonIndex)")
        selectingForIndex = buttonIndex
        
        // 计算所有屏幕的组合边界
        var combinedFrame = CGRect.zero
        for screen in NSScreen.screens {
            combinedFrame = combinedFrame.union(screen.frame)
        }
        
        Logger.shared.log("📐 所有屏幕组合尺寸: \(combinedFrame)")
        Logger.shared.log("📐 屏幕数量: \(NSScreen.screens.count)")
        
        // 创建全屏覆盖窗口
        let window = NSWindow(
            contentRect: combinedFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.2)
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let contentView = WindowSelectionOverlay(frame: combinedFrame)
        contentView.onWindowSelected = { [weak self] windowID, pid, appName, title in
            self?.handleWindowSelected((windowID, pid, appName, title))
        }
        contentView.onCancel = { [weak self] in
            self?.cancelSelection()
        }
        
        window.contentView = contentView
        selectorWindow = window
        
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
        NSCursor.crosshair.set()
    }
    
    private func handleWindowSelected(_ info: (windowID: UInt32, pid: Int32, appName: String, title: String)) {
        let titleDisplay = info.title.isEmpty ? "(无标题)" : info.title
        
        // 获取窗口的位置和大小信息
        var position: CGPoint?
        var size: CGSize?
        if let windowInfo = CGWindowListCopyWindowInfo([.optionIncludingWindow], info.windowID) as? [[String: Any]],
           let windowData = windowInfo.first,
           let boundsDict = windowData[kCGWindowBounds as String] as? [String: Any],
           let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
            position = bounds.origin
            size = bounds.size
            Logger.shared.log("✅ 窗口已选择: 应用=\(info.appName), 标题=\(titleDisplay), ID=\(info.windowID), PID=\(info.pid), 位置=(\(bounds.origin.x), \(bounds.origin.y)), 大小=(\(bounds.size.width)x\(bounds.size.height))")
        } else {
            Logger.shared.log("✅ 窗口已选择: 应用=\(info.appName), 标题=\(titleDisplay), ID=\(info.windowID), PID=\(info.pid)")
        }
        
        if let index = selectingForIndex {
            Logger.shared.log("💾 保存窗口绑定: buttonIndex=\(index)")
            FloatingButtonConfigManager.shared.bindWindow(
                index: index,
                windowID: info.windowID,
                pid: info.pid,
                appName: info.appName,
                windowTitle: info.title,
                position: position,
                size: size
            )
        }
        cancelSelection()
    }
    
    private func cancelSelection() {
        selectorWindow?.orderOut(nil)
        selectorWindow = nil
        selectingForIndex = nil
        NSCursor.arrow.set()
    }
    
    // MARK: - 窗口显隐控制
    
    func handleToggleWindow(for buttonIndex: Int) {
        Logger.shared.log("🪟 WindowManager.handleToggleWindow: buttonIndex=\(buttonIndex)")
        
        // 任何控制窗口相关的操作（包括绑定和控制）都需要辅助功能权限
        if !InputMonitor.hasAccessibilityPermission() {
            Logger.shared.log("❌ 没有辅助功能权限，请求权限")
            requestAccessibilityPermission()
            return
        }
        
        let config = FloatingButtonConfigManager.shared.config
        
        guard let boundWindow = config.boundWindows[buttonIndex] else {
            Logger.shared.log("⚠️ 没有绑定窗口，启动窗口选择")
            // 没有绑定窗口，启动选择
            startWindowSelection(for: buttonIndex)
            return
        }
        
        Logger.shared.log("✅ 找到绑定窗口: windowID=\(boundWindow.windowID), app=\(boundWindow.appName)")
        
        // 检查窗口是否存在
        if !isWindowExists(windowID: boundWindow.windowID, pid: boundWindow.pid, windowTitle: boundWindow.windowTitle, initialPosition: boundWindow.initialPosition, initialSize: boundWindow.initialSize) {
            Logger.shared.log("❌ 窗口不存在: windowID=\(boundWindow.windowID)")
            // 窗口不存在，清除绑定并重新选择
            FloatingButtonConfigManager.shared.unbindWindow(index: buttonIndex)
            showAlert(title: L10n.tr("window.closed"), message: L10n.tr("window.closedMsg"))
            return
        }
        
        Logger.shared.log("✅ 窗口存在，开始切换显隐状态")
        // 切换窗口显隐状态
        toggleWindowVisibility(
            windowID: boundWindow.windowID, 
            pid: boundWindow.pid, 
            windowTitle: boundWindow.windowTitle,
            initialPosition: boundWindow.initialPosition,
            initialSize: boundWindow.initialSize
        )
    }
    
    private func isWindowExists(windowID: UInt32, pid: Int32, windowTitle: String?, initialPosition: CGPoint? = nil, initialSize: CGSize? = nil) -> Bool {
        // 使用 Accessibility API 检测窗口是否存在（包括最小化的窗口）
        let appRef = AXUIElementCreateApplication(pid)
        let element = findWindowElement(appRef: appRef, windowID: windowID, windowTitle: windowTitle, initialPosition: initialPosition, initialSize: initialSize)
        return element != nil
    }
    
    private func toggleWindowVisibility(windowID: UInt32, pid: Int32, windowTitle: String?, initialPosition: CGPoint?, initialSize: CGSize?) {
        Logger.shared.log("🔄 切换窗口显隐: windowID=\(windowID), pid=\(pid), title=\(windowTitle ?? "nil")")
        let appRef = AXUIElementCreateApplication(pid)
        
        // 查找窗口元素
        guard let windowElement = findWindowElement(appRef: appRef, windowID: windowID, windowTitle: windowTitle, initialPosition: initialPosition, initialSize: initialSize) else {
            Logger.shared.log("❌ 无法找到窗口元素")
            return
        }
        
        Logger.shared.log("✅ 找到窗口元素")
        
        // 检查窗口是否最小化
        var isMinimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, kAXMinimizedAttribute as CFString, &isMinimized) == .success,
           let minimized = isMinimized as? Bool {
            
            Logger.shared.log("📊 窗口状态: 最小化=\(minimized)")
            
            if minimized {
                // 窗口已最小化，显示它
                Logger.shared.log("👁️ 窗口已最小化，执行显示操作")
                showWindow(windowElement: windowElement, pid: pid)
            } else {
                // 窗口可见，检查是否是主窗口（前置状态）
                // 先检查应用是否激活
                let app = NSRunningApplication(processIdentifier: pid)
                let isAppActive = app?.isActive ?? false
                Logger.shared.log("📊 应用激活状态: active=\(isAppActive)")
                
                if !isAppActive {
                    // 应用未激活，前置窗口
                    Logger.shared.log("⬆️ 应用未激活，执行前置操作")
                    showWindow(windowElement: windowElement, pid: pid)
                } else {
                    // 应用已激活，检查窗口是否是主窗口
                    var isMain: CFTypeRef?
                    if AXUIElementCopyAttributeValue(windowElement, kAXMainAttribute as CFString, &isMain) == .success,
                       let main = isMain as? Bool {
                        
                        Logger.shared.log("📊 窗口主窗口状态: main=\(main)")
                        
                        if main {
                            // 窗口是主窗口，最小化它
                            Logger.shared.log("🙈 窗口是主窗口，执行最小化操作")
                            hideWindow(windowElement: windowElement)
                        } else {
                            // 窗口不是主窗口，前置它
                            Logger.shared.log("⬆️ 窗口不是主窗口，执行前置操作")
                            showWindow(windowElement: windowElement, pid: pid)
                        }
                    } else {
                        // 无法获取主窗口状态，默认前置窗口
                        Logger.shared.log("⚠️ 无法获取主窗口状态，默认执行前置操作")
                        showWindow(windowElement: windowElement, pid: pid)
                    }
                }
            }
        } else {
            Logger.shared.log("⚠️ 无法获取最小化状态，尝试显示窗口")
            // 无法获取最小化状态，尝试切换
            showWindow(windowElement: windowElement, pid: pid)
        }
    }
    
    private func findWindowElement(appRef: AXUIElement, windowID: UInt32, windowTitle: String?, initialPosition: CGPoint?, initialSize: CGSize?) -> AXUIElement? {
        Logger.shared.log("🔍 查找窗口元素: windowID=\(windowID), title=\(windowTitle ?? "nil")")
        
        // 第一步：尝试通过绑定的windowID直接获取当前位置
        var targetPosition: CGPoint?
        var targetSize: CGSize?
        
        if let windowInfo = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
           let info = windowInfo.first,
           let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
           let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
            targetPosition = bounds.origin
            targetSize = bounds.size
            Logger.shared.log("  ✅ 绑定的windowID=\(windowID)仍然存在，位置=(\(bounds.origin.x), \(bounds.origin.y)), 大小=(\(bounds.size.width)x\(bounds.size.height))")
        } else {
            Logger.shared.log("  ⚠️ 绑定的windowID=\(windowID)不存在，尝试其他匹配方式")
            // windowID不存在，尝试使用保存的初始位置
            targetPosition = initialPosition
            targetSize = initialSize
        }
        
        let attributes = [kAXWindowsAttribute as CFString, "AXMinimizedWindows" as CFString]
        
        for attr in attributes {
            Logger.shared.log("  检查属性: \(attr)")
            var windows: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appRef, attr, &windows)
            
            if result == .success,
               let windowElements = windows as? [AXUIElement] {
                Logger.shared.log("  找到 \(windowElements.count) 个窗口")
                
                // 策略1：如果有位置信息，通过位置精确匹配
                if let targetPos = targetPosition, let targetSz = targetSize {
                    for (index, windowElement) in windowElements.enumerated() {
                        var posValue: CFTypeRef?
                        var sizeValue: CFTypeRef?
                        
                        if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posValue) == .success,
                           AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success {
                            
                            var pos = CGPoint.zero
                            var size = CGSize.zero
                            AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
                            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                            
                            Logger.shared.log("    窗口[\(index)]: 位置=(\(pos.x), \(pos.y)), 大小=(\(size.width)x\(size.height))")
                            
                            // 位置和大小都匹配（允许小误差）
                            if abs(pos.x - targetPos.x) < 5 && abs(pos.y - targetPos.y) < 5 &&
                               abs(size.width - targetSz.width) < 5 && abs(size.height - targetSz.height) < 5 {
                                Logger.shared.log("  ✅ 通过位置和大小找到匹配的窗口元素!")
                                return windowElement
                            }
                        }
                    }
                }
                
                // 策略2：通过标题匹配，然后检查每个匹配窗口的ID
                if let title = windowTitle, !title.isEmpty {
                    var matchedElements: [(element: AXUIElement, index: Int)] = []
                    
                    for (index, windowElement) in windowElements.enumerated() {
                        var titleValue: CFTypeRef?
                        if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue) == .success,
                           let elementTitle = titleValue as? String {
                            Logger.shared.log("    窗口[\(index)]: 标题=\(elementTitle)")
                            if elementTitle == title {
                                matchedElements.append((windowElement, index))
                            }
                        }
                    }
                    
                    if matchedElements.count == 1 {
                        Logger.shared.log("  ✅ 通过标题找到唯一匹配的窗口元素!")
                        return matchedElements[0].element
                    } else if matchedElements.count > 1 {
                        Logger.shared.log("  ⚠️ 找到 \(matchedElements.count) 个同标题窗口，尝试通过位置匹配")
                        
                        // 对于多个同标题窗口，获取它们的位置，与CG API中的窗口对比
                        let allWindowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                        
                        for (windowElement, index) in matchedElements {
                            var posValue: CFTypeRef?
                            var sizeValue: CFTypeRef?
                            
                            if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posValue) == .success,
                               AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success {
                                
                                var pos = CGPoint.zero
                                var size = CGSize.zero
                                AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
                                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                                
                                // 在CG窗口列表中查找匹配的窗口ID
                                for windowInfo in allWindowList {
                                    guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                                          let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                                          let cgWindowID = windowInfo[kCGWindowNumber as String] as? UInt32 else { continue }
                                    
                                    // 位置和大小匹配
                                    if abs(bounds.origin.x - pos.x) < 5 && abs(bounds.origin.y - pos.y) < 5 &&
                                       abs(bounds.size.width - size.width) < 5 && abs(bounds.size.height - size.height) < 5 {
                                        Logger.shared.log("    窗口[\(index)]对应的CG windowID=\(cgWindowID)")
                                        
                                        // 检查是否与绑定的windowID一致
                                        if cgWindowID == windowID {
                                            Logger.shared.log("  ✅ 通过windowID匹配找到目标窗口!")
                                            return windowElement
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 如果windowID匹配失败，返回第一个匹配的窗口
                        Logger.shared.log("  ⚠️ 无法通过windowID精确匹配，使用第一个同标题窗口")
                        return matchedElements[0].element
                    }
                }
                
                // 策略3：如果只有一个窗口，直接返回
                if windowElements.count == 1 {
                    Logger.shared.log("  ✅ 只有一个窗口，直接返回!")
                    return windowElements[0]
                }
            }
        }
        
        Logger.shared.log("❌ 未找到匹配的窗口元素")
        return nil
    }
    
    private func showWindow(windowElement: AXUIElement, pid: Int32) {
        let app = NSRunningApplication(processIdentifier: pid)
        
        // 1. 取消最小化
        AXUIElementSetAttributeValue(windowElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        
        // 2. 激活应用
        if app?.isHidden == true {
            app?.unhide()
        }
        app?.activate()
        
        // 3. 将窗口置顶
        AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(windowElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(windowElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
    
    private func hideWindow(windowElement: AXUIElement) {
        // 最小化窗口
        AXUIElementSetAttributeValue(windowElement, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }
    
    // MARK: - 权限请求
    
    func requestAccessibilityPermission() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("permission.required")
        alert.informativeText = L10n.tr("permission.requiredMsg")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("permission.openSystemSettings"))
        alert.addButton(withTitle: L10n.tr("permission.later"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 触发系统权限申请
            let options = ["AXTrustedCheckOptionPrompt": true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            // 打开系统设置
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        
        // 弹窗结束后，发送通知告知权限可能已变更（无论用户点击了什么，回来时都应该检查一下）
        NotificationCenter.default.post(name: NSNotification.Name("accessibilityPermissionChanged"), object: nil)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }
}

// MARK: - 窗口选择覆盖层

class WindowSelectionOverlay: NSView {
    var onWindowSelected: ((UInt32, Int32, String, String) -> Void)?
    var onCancel: (() -> Void)?
    
    private var hoveredWindow: (id: UInt32, title: String, app: String)?
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTracking()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTracking()
    }
    
    private func setupTracking() {
        let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    private func getWindowTitleFromAX(pid: Int32, windowID: UInt32) -> String? {
        let appRef = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windows) == .success,
           let windowElements = windows as? [AXUIElement] {
            for windowElement in windowElements {
                var titleValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue) == .success,
                   let title = titleValue as? String {
                    return title
                }
            }
        }
        return nil
    }
    
    override func mouseMoved(with event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        
        var found = false
        for info in windowList {
            guard let windowLayer = info[kCGWindowLayer as String] as? Int, windowLayer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            
            // CGWindowListCopyWindowInfo 返回的坐标系统已经是 CoreGraphics 坐标系统（底部为原点）
            // NSEvent.mouseLocation 也是 CoreGraphics 坐标系统
            // 所以可以直接比较，不需要转换
            let point = mouseLocation
            
            if bounds.contains(point) {
                if let windowID = info[kCGWindowNumber as String] as? UInt32,
                   let ownerName = info[kCGWindowOwnerName as String] as? String,
                   let pid = info[kCGWindowOwnerPID as String] as? Int32 {
                    if ownerName == "AIX" { continue }
                    
                    // 先尝试从 CG API 获取标题
                    var windowTitle = info[kCGWindowName as String] as? String ?? ""
                    
                    // 如果标题为空，尝试从 AX API 获取
                    if windowTitle.isEmpty {
                        windowTitle = getWindowTitleFromAX(pid: pid, windowID: windowID) ?? ""
                    }
                    
                    hoveredWindow = (windowID, windowTitle, ownerName)
                    found = true
                    break
                }
            }
        }
        
        if !found {
            hoveredWindow = nil
        }
        needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        
        for info in windowList {
            guard let windowLayer = info[kCGWindowLayer as String] as? Int, windowLayer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            
            // CGWindowListCopyWindowInfo 返回的坐标系统已经是 CoreGraphics 坐标系统（底部为原点）
            // NSEvent.mouseLocation 也是 CoreGraphics 坐标系统
            // 所以可以直接比较，不需要转换
            let point = mouseLocation
            
            if bounds.contains(point) {
                if let windowID = info[kCGWindowNumber as String] as? UInt32,
                   let ownerName = info[kCGWindowOwnerName as String] as? String,
                   let pid = info[kCGWindowOwnerPID as String] as? Int32 {
                    if ownerName == "AIX" { continue }
                    
                    // 先尝试从 CG API 获取标题
                    var windowTitle = info[kCGWindowName as String] as? String ?? ""
                    
                    // 如果标题为空，尝试从 AX API 获取
                    if windowTitle.isEmpty {
                        windowTitle = getWindowTitleFromAX(pid: pid, windowID: windowID) ?? ""
                    }
                    
                    onWindowSelected?(windowID, pid, ownerName, windowTitle)
                    return
                }
            }
        }
        
        // 没有点击到窗口，取消选择
        onCancel?()
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // 绘制提示文字
        let mainText = "请点击要绑定的窗口"
        let mainAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 28),
            .foregroundColor: NSColor.white
        ]
        let mainSize = mainText.size(withAttributes: mainAttributes)
        let mainRect = NSRect(
            x: (bounds.width - mainSize.width) / 2,
            y: (bounds.height - mainSize.height) / 2 + 50,
            width: mainSize.width,
            height: mainSize.height
        )
        mainText.draw(in: mainRect, withAttributes: mainAttributes)
        
        // 绘制取消提示
        let cancelText = "点击任意位置取消"
        let cancelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7)
        ]
        let cancelSize = cancelText.size(withAttributes: cancelAttributes)
        let cancelRect = NSRect(
            x: (bounds.width - cancelSize.width) / 2,
            y: (bounds.height - cancelSize.height) / 2 + 10,
            width: cancelSize.width,
            height: cancelSize.height
        )
        cancelText.draw(in: cancelRect, withAttributes: cancelAttributes)
        
        // 绘制当前指向的窗口信息
        if let info = hoveredWindow {
            let titleDisplay = info.title.isEmpty ? "(无标题)" : info.title
            let infoText = "应用: \(info.app)\n标题: \(titleDisplay)\n窗口ID: \(info.id)"
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let infoAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: NSColor.cyan,
                .paragraphStyle: paragraphStyle
            ]
            
            let infoSize = infoText.size(withAttributes: infoAttributes)
            let infoRect = NSRect(
                x: (bounds.width - infoSize.width) / 2,
                y: (bounds.height - infoSize.height) / 2 - 50,
                width: infoSize.width,
                height: infoSize.height
            )
            
            // 绘制背景框
            let bgRect = infoRect.insetBy(dx: -20, dy: -15)
            let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 10, yRadius: 10)
            NSColor.black.withAlphaComponent(0.7).set()
            bgPath.fill()
            
            infoText.draw(in: infoRect, withAttributes: infoAttributes)
        }
    }
}
