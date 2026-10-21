import Foundation
import AppKit
import QuartzCore

/// 悬浮球组贴边隐藏管理器
/// 开启贴边隐藏的分组在松手时贴近屏幕边缘（左/右/上）即整组滑出屏幕隐藏，
/// 鼠标移入对应边缘热区或靠近成员/笔记窗口时唤回显示
@MainActor
final class EdgeHideManager {
    static let shared = EdgeHideManager()

    // MARK: - 常量

    /// 松手判定贴边距离（包围盒对应边与屏幕边缘的距离阈值）
    let edgeTriggerDistance: CGFloat = 20
    /// 屏幕边缘热区宽度（鼠标进入该条带唤回隐藏分组）
    let hotZoneWidth: CGFloat = 20
    /// 滑出/滑回动画时长
    let animationDuration: TimeInterval = 0.25
    /// 保持显示区域外扩边距（鼠标靠近成员窗口/笔记窗口时保持显示）
    let keepVisibleMargin: CGFloat = 8
    /// 热区监听回调节流间隔
    let monitorThrottleInterval: TimeInterval = 0.05

    /// 贴边方向
    enum EdgeSide: String, Codable {
        case left, right, top
    }

    /// 可序列化的二维坐标点
    struct CodablePoint: Codable, Equatable {
        var x: Double
        var y: Double

        init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        init(_ point: CGPoint) {
            self.x = Double(point.x)
            self.y = Double(point.y)
        }

        var cgPoint: CGPoint {
            CGPoint(x: x, y: y)
        }
    }

    /// 分组隐藏状态（持久化）
    struct HiddenState: Codable {
        /// 隐藏到的屏幕边缘
        var edge: EdgeSide
        /// 隐藏时所在屏幕的 frame（含菜单栏的完整 frame）
        var screenFrame: CGRect
        /// 成员索引快照（分组被删/解散时用于恢复窗口）
        var memberIndices: [Int]
        /// 统一滑出位移向量（所有成员与列表窗口共用同一向量，保证相对位置不变）
        var slideOffset: CGSize
        /// 各成员在贴边吸附时的正常屏幕内显示位置（key 为 buttonIndex）
        var revealedOrigins: [Int: CodablePoint]

        /// CGRect / CGSize 不是 Codable，手动展开编码
        enum CodingKeys: String, CodingKey {
            case edge
            case screenFrameX
            case screenFrameY
            case screenFrameWidth
            case screenFrameHeight
            case memberIndices
            case slideOffsetWidth
            case slideOffsetHeight
            case revealedOrigins
        }

        init(edge: EdgeSide, screenFrame: CGRect, memberIndices: [Int], slideOffset: CGSize, revealedOrigins: [Int: CodablePoint]) {
            self.edge = edge
            self.screenFrame = screenFrame
            self.memberIndices = memberIndices
            self.slideOffset = slideOffset
            self.revealedOrigins = revealedOrigins
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            edge = try container.decode(EdgeSide.self, forKey: .edge)
            screenFrame = CGRect(
                x: try container.decode(Double.self, forKey: .screenFrameX),
                y: try container.decode(Double.self, forKey: .screenFrameY),
                width: try container.decode(Double.self, forKey: .screenFrameWidth),
                height: try container.decode(Double.self, forKey: .screenFrameHeight)
            )
            memberIndices = try container.decode([Int].self, forKey: .memberIndices)
            slideOffset = CGSize(
                width: try container.decode(Double.self, forKey: .slideOffsetWidth),
                height: try container.decode(Double.self, forKey: .slideOffsetHeight)
            )
            revealedOrigins = try container.decodeIfPresent([Int: CodablePoint].self, forKey: .revealedOrigins) ?? [:]
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(edge, forKey: .edge)
            try container.encode(Double(screenFrame.origin.x), forKey: .screenFrameX)
            try container.encode(Double(screenFrame.origin.y), forKey: .screenFrameY)
            try container.encode(Double(screenFrame.width), forKey: .screenFrameWidth)
            try container.encode(Double(screenFrame.height), forKey: .screenFrameHeight)
            try container.encode(memberIndices, forKey: .memberIndices)
            try container.encode(Double(slideOffset.width), forKey: .slideOffsetWidth)
            try container.encode(Double(slideOffset.height), forKey: .slideOffsetHeight)
            try container.encode(revealedOrigins, forKey: .revealedOrigins)
        }
    }

    // MARK: - 状态

    /// 持久化键：值为 JSONEncoder 编码的 [String: HiddenState]（key = groupId.uuidString）
    private let storageKey = "edgeHide_hiddenStates"

    /// 当前处于贴边隐藏状态的分组
    private var hiddenStates: [UUID: HiddenState] = [:]
    /// 各分组当前是否被热区唤回显示（不持久化）
    private var isRevealed: [UUID: Bool] = [:]
    /// 各分组在刚贴边松手隐藏后，是否正在等待鼠标移出边缘区域（抑制松手瞬间反向弹出）
    private var isWaitingForMouseExit: [UUID: Bool] = [:]
    /// 依附于各分组的笔记/列表窗口在隐藏前记录的显示位置
    private var hiddenNoteOrigins: [UUID: CGPoint] = [:]

    /// 笔记/列表窗口提供者（由 AppDelegate 注入，用于列表窗口同步移动）
    var noteWindowProvider: (() -> (note: NSWindow?, attachedTo: NSWindow?))?

    /// 全局鼠标移动监听（其他应用中的移动）
    private var globalMonitor: Any?
    /// 本地鼠标移动监听（本应用中的移动）
    private var localMonitor: Any?
    /// 节流：上次处理鼠标位置的时间
    private var lastMonitorProcessTime: Date = .distantPast

    // MARK: - 初始化

    private init() {
        loadHiddenStates()

        // 悬浮球拖拽结束：判定是否贴边隐藏整组
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDragEndNotification(_:)),
            name: FloatingWindow.dragEndNotification,
            object: nil
        )

        // 悬浮球开始拖拽：若唤回状态下被拖动则立即解除贴边隐藏
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDragNotification(_:)),
            name: FloatingWindow.dragNotification,
            object: nil
        )

        // 配置变化：同步/清理隐藏状态
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChangedNotification(_:)),
            name: Notification.Name("floatingButtonConfigChanged"),
            object: nil
        )

        // 屏幕参数变化：对隐藏分组兜底重算
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChangedNotification(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - 通知回调

    /// 悬浮球拖拽结束（仅处理真实拖拽，发送方在 userInfo 中携带 isRealDrag 标记）
    @objc private func handleDragEndNotification(_ notification: Notification) {
        guard notification.userInfo?["isRealDrag"] as? Bool == true else { return }
        guard let window = notification.object as? NSWindow else { return }
        handleDragEnd(window)
    }

    /// 悬浮球拖拽移动中：一旦发生位移立即解除旧贴边隐藏状态，避免用户拖动时与贴边动画打架
    @objc private func handleDragNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let buttonIndex = buttonIndexForWindow(window) else { return }
        let configManager = FloatingButtonConfigManager.shared
        guard let group = configManager.getGroup(for: buttonIndex) else { return }

        if hiddenStates[group.id] != nil {
            hiddenStates.removeValue(forKey: group.id)
            isRevealed.removeValue(forKey: group.id)
            isWaitingForMouseExit.removeValue(forKey: group.id)
            hiddenNoteOrigins.removeValue(forKey: group.id)
            persistHiddenStates()
            if hiddenStates.isEmpty { stopMouseMonitor() }
            Logger.shared.log("📍 贴边隐藏：分组「\(group.name)」拖离边缘，解除贴边隐藏状态")
        }
    }

    /// 悬浮球配置变化
    @objc private func handleConfigChangedNotification(_ notification: Notification) {
        handleConfigChanged()
    }

    /// 屏幕参数变化（分辨率调整、显示器插拔等）
    @objc private func handleScreenParametersChangedNotification(_ notification: Notification) {
        handleScreenParametersChanged()
    }

    // MARK: - 拖拽结束处理

    private func handleDragEnd(_ window: NSWindow) {
        guard let buttonIndex = buttonIndexForWindow(window) else { return }
        let configManager = FloatingButtonConfigManager.shared
        guard let group = configManager.getGroup(for: buttonIndex) else { return }

        // 该分组此前处于隐藏状态 → 先视为解除旧状态（后续重新判定）
        if hiddenStates[group.id] != nil {
            hiddenStates.removeValue(forKey: group.id)
            isRevealed.removeValue(forKey: group.id)
            isWaitingForMouseExit.removeValue(forKey: group.id)
            hiddenNoteOrigins.removeValue(forKey: group.id)
            persistHiddenStates()
            if hiddenStates.isEmpty { stopMouseMonitor() }
            Logger.shared.log("📍 贴边隐藏：分组「\(group.name)」拖拽后解除旧隐藏状态，重新判定")
        }

        // 分组未开启贴边隐藏 → 无需动作，直接返回
        guard configManager.isEdgeHideEnabled(for: buttonIndex) else { return }

        // 收集组成员窗口并计算包围盒
        let memberWindows = group.memberIndices.compactMap { windowForButtonIndex($0) }
        guard !memberWindows.isEmpty else { return }
        var union = memberWindows[0].frame
        for memberWindow in memberWindows.dropFirst() {
            union = union.union(memberWindow.frame)
        }

        // 统一以含菜单栏的完整 screen.frame 为基准（顶部滑出要越过菜单栏，热区同样基于 frame 顶部）
        guard let screenFrame = (window.screen ?? NSScreen.main)?.frame else { return }

        // 判定贴近三边：计算包围盒对应边与屏幕边缘的距离
        let leftDist = max(0, union.minX - screenFrame.minX)
        let rightDist = max(0, screenFrame.maxX - union.maxX)
        let topDist = max(0, screenFrame.maxY - union.maxY)

        var candidates: [(edge: EdgeSide, distance: CGFloat)] = []
        if union.minX <= screenFrame.minX + edgeTriggerDistance {
            candidates.append((.left, leftDist))
        }
        if union.maxX >= screenFrame.maxX - edgeTriggerDistance {
            candidates.append((.right, rightDist))
        }
        if union.maxY >= screenFrame.maxY - edgeTriggerDistance {
            candidates.append((.top, topDist))
        }

        guard let hit = candidates.min(by: { $0.distance < $1.distance }) else {
            // 未贴近任何边缘 → 保持正常显示，不隐藏
            return
        }
        let edge = hit.edge

        // 1. 吸附对齐到边缘，并确保在屏幕范围内
        var alignDelta = CGSize.zero
        switch edge {
        case .left:
            alignDelta.width = screenFrame.minX - union.minX
            let newMinY = max(screenFrame.minY, min(union.minY, screenFrame.maxY - union.height))
            alignDelta.height = newMinY - union.minY
        case .right:
            alignDelta.width = screenFrame.maxX - union.maxX
            let newMinY = max(screenFrame.minY, min(union.minY, screenFrame.maxY - union.height))
            alignDelta.height = newMinY - union.minY
        case .top:
            alignDelta.height = screenFrame.maxY - union.maxY
            let newMinX = max(screenFrame.minX, min(union.minX, screenFrame.maxX - union.width))
            alignDelta.width = newMinX - union.minX
        }

        // 2. 计算吸附对齐后的屏幕内显示位置 (revealedOrigins)，并持久化各球真实位置
        var revealedOrigins: [Int: CodablePoint] = [:]
        for memberWindow in memberWindows {
            guard let idx = buttonIndexForWindow(memberWindow) else { continue }
            let alignedPoint = CGPoint(
                x: memberWindow.frame.origin.x + alignDelta.width,
                y: memberWindow.frame.origin.y + alignDelta.height
            )
            revealedOrigins[idx] = CodablePoint(alignedPoint)
            saveNormalPosition(alignedPoint, for: idx)
        }
        let alignedUnion = union.offsetBy(dx: alignDelta.width, dy: alignDelta.height)

        // 3. 计算统一滑出向量：把对齐后的包围盒完全移出 screen.frame
        let slideOffset = slideOutOffset(for: edge, union: alignedUnion, screenFrame: screenFrame)

        // 4. 记录隐藏状态与等待鼠标移开标记
        let state = HiddenState(
            edge: edge,
            screenFrame: screenFrame,
            memberIndices: group.memberIndices,
            slideOffset: slideOffset,
            revealedOrigins: revealedOrigins
        )
        hiddenStates[group.id] = state
        isRevealed[group.id] = false
        // 关键：拖拽刚松手，鼠标就在边缘停留，必须等待鼠标离开边缘区域后才允许唤回，彻底杜绝反向弹出
        isWaitingForMouseExit[group.id] = true

        // 5. 动画滑出屏幕外
        animateToHidden(groupId: group.id, state: state, memberWindows: memberWindows)

        persistHiddenStates()
        startMouseMonitor()
        Logger.shared.log("📍 贴边隐藏：分组「\(group.name)」已吸附并滑出至\(edgeDescription(edge))边缘隐藏（等待鼠标移开）")
    }

    // MARK: - 配置变化处理

    private func handleConfigChanged() {
        guard !hiddenStates.isEmpty else {
            stopMouseMonitor()
            return
        }

        let configManager = FloatingButtonConfigManager.shared
        let buttonCount = configManager.config.buttonCount
        var didChange = false

        for (groupId, state) in hiddenStates {
            if let group = configManager.config.buttonGroups.first(where: { $0.id == groupId }) {
                if group.enableEdgeHide {
                    // 分组存在且开启：同步成员快照为当前组成员（过滤无效索引）
                    let newMembers = group.memberIndices.filter { $0 < buttonCount }
                    let removedMembers = state.memberIndices.filter { !newMembers.contains($0) }
                    if !removedMembers.isEmpty && isRevealed[groupId] != true {
                        let removedWindows = removedMembers.compactMap { windowForButtonIndex($0) }
                        var targets: [(window: NSWindow, target: CGPoint)] = []
                        for win in removedWindows {
                            if let idx = buttonIndexForWindow(win), let orig = state.revealedOrigins[idx]?.cgPoint {
                                targets.append((win, orig))
                            } else {
                                let cur = win.frame.origin
                                targets.append((win, CGPoint(x: cur.x - state.slideOffset.width, y: cur.y - state.slideOffset.height)))
                            }
                        }
                        animateWindows(targets: targets, noteTarget: nil)
                        Logger.shared.log("📍 贴边隐藏：成员 \(removedMembers) 已移出分组，滑回屏幕内")
                    }
                    if state.memberIndices != newMembers {
                        var newState = state
                        newState.memberIndices = newMembers
                        hiddenStates[groupId] = newState
                        didChange = true
                    }
                } else {
                    // 分组存在但已关闭贴边隐藏 → 滑回并清除状态
                    restoreGroup(groupId, state: state, reason: "分组已关闭贴边隐藏")
                    didChange = true
                }
            } else {
                // 分组已不存在（被删除/解散）→ 用 memberIndices 快照找到窗口滑回
                restoreGroup(groupId, state: state, reason: "分组已删除")
                didChange = true
            }
        }

        if didChange { persistHiddenStates() }
        if hiddenStates.isEmpty { stopMouseMonitor() }
    }

    /// 把隐藏分组滑回屏幕内并清理状态（分组删除 / 开关关闭场景）
    private func restoreGroup(_ groupId: UUID, state: HiddenState, reason: String) {
        let memberWindows = state.memberIndices.compactMap { windowForButtonIndex($0) }
        var targets: [(window: NSWindow, target: CGPoint)] = []
        for window in memberWindows {
            if let idx = buttonIndexForWindow(window), let origin = state.revealedOrigins[idx]?.cgPoint {
                targets.append((window, origin))
            } else {
                let current = window.frame.origin
                targets.append((window, CGPoint(x: current.x - state.slideOffset.width, y: current.y - state.slideOffset.height)))
            }
        }
        animateWindows(targets: targets, noteTarget: nil)
        hiddenStates.removeValue(forKey: groupId)
        isRevealed.removeValue(forKey: groupId)
        isWaitingForMouseExit.removeValue(forKey: groupId)
        hiddenNoteOrigins.removeValue(forKey: groupId)
        Logger.shared.log("📍 贴边隐藏：\(reason)，成员 \(state.memberIndices) 已滑回屏幕内并清理状态")
    }

    // MARK: - 屏幕参数变化处理

    private func handleScreenParametersChanged() {
        guard !hiddenStates.isEmpty else { return }
        let screens = NSScreen.screens
        var didChange = false

        for (groupId, state) in hiddenStates {
            if isRevealed[groupId] == true { continue }
            let memberWindows = state.memberIndices.compactMap { windowForButtonIndex($0) }
            guard !memberWindows.isEmpty else { continue }
            var union = memberWindows[0].frame
            for memberWindow in memberWindows.dropFirst() {
                union = union.union(memberWindow.frame)
            }

            let referenceScreen = screens.first { $0.frame == state.screenFrame }
                ?? memberWindows[0].screen
                ?? NSScreen.main
            guard let referenceScreen else { continue }
            let referenceFrame = referenceScreen.frame

            if referenceFrame == state.screenFrame && !union.intersects(referenceFrame) { continue }

            if union.intersects(referenceFrame) {
                let slide = slideOutOffset(for: state.edge, union: union, screenFrame: referenceFrame)
                var targets: [(window: NSWindow, target: CGPoint)] = []
                for win in memberWindows {
                    let cur = win.frame.origin
                    targets.append((win, CGPoint(x: cur.x + slide.width, y: cur.y + slide.height)))
                }
                animateWindows(targets: targets, noteTarget: nil)
                var newState = state
                newState.screenFrame = referenceFrame
                newState.slideOffset = slide
                hiddenStates[groupId] = newState
                Logger.shared.log("📍 贴边隐藏：屏幕参数变化，隐藏分组已重新滑出屏幕")
            } else {
                let revealedUnion = edgeRevealedRect(union: union, edge: state.edge, screenFrame: referenceFrame)
                let slide = slideOutOffset(for: state.edge, union: revealedUnion, screenFrame: referenceFrame)
                let translation = CGSize(
                    width: revealedUnion.minX + slide.width - union.minX,
                    height: revealedUnion.minY + slide.height - union.minY
                )
                var targets: [(window: NSWindow, target: CGPoint)] = []
                for win in memberWindows {
                    let cur = win.frame.origin
                    targets.append((win, CGPoint(x: cur.x + translation.width, y: cur.y + translation.height)))
                }
                animateWindows(targets: targets, noteTarget: nil)
                var newState = state
                newState.screenFrame = referenceFrame
                newState.slideOffset = slide
                hiddenStates[groupId] = newState
                Logger.shared.log("📍 贴边隐藏：屏幕参数变化，隐藏分组已按新屏幕重新归位")
            }
            didChange = true
        }

        if didChange { persistHiddenStates() }
    }

    // MARK: - 启动恢复

    /// 启动时恢复持久化的隐藏状态（由 AppDelegate 在悬浮球窗口创建完成后调用）
    func restoreOnLaunch(floatingWindows: [NSWindow]) {
        let configManager = FloatingButtonConfigManager.shared
        let buttonCount = configManager.config.buttonCount

        var windowByIndex: [Int: NSWindow] = [:]
        for window in floatingWindows {
            if let index = buttonIndexForWindow(window) {
                windowByIndex[index] = window
            }
        }

        var restoredStates: [UUID: HiddenState] = [:]
        for (groupId, state) in hiddenStates {
            guard let group = configManager.config.buttonGroups.first(where: { $0.id == groupId }),
                  group.enableEdgeHide else { continue }
            let validMembers = state.memberIndices.filter { $0 >= 0 && $0 < buttonCount && windowByIndex[$0] != nil }
            guard !validMembers.isEmpty else { continue }
            var restored = state
            restored.memberIndices = validMembers
            restoredStates[groupId] = restored
        }

        hiddenStates = restoredStates
        isRevealed = restoredStates.mapValues { _ in false }
        isWaitingForMouseExit = [:]

        guard !hiddenStates.isEmpty else {
            persistHiddenStates()
            Logger.shared.log("📍 贴边隐藏：启动恢复完成，无有效隐藏分组")
            return
        }

        // 把成员窗口直接放置在屏幕外隐藏位置
        for state in hiddenStates.values {
            for index in state.memberIndices {
                guard let window = windowByIndex[index] else { continue }
                if let revealedOrigin = state.revealedOrigins[index]?.cgPoint {
                    let hiddenOrigin = CGPoint(
                        x: revealedOrigin.x + state.slideOffset.width,
                        y: revealedOrigin.y + state.slideOffset.height
                    )
                    window.setFrameOrigin(hiddenOrigin)
                } else {
                    let current = window.frame
                    if current.intersects(state.screenFrame) {
                        window.setFrameOrigin(CGPoint(
                            x: current.minX + state.slideOffset.width,
                            y: current.minY + state.slideOffset.height
                        ))
                    }
                }
            }
        }

        persistHiddenStates()
        startMouseMonitor()
        Logger.shared.log("📍 贴边隐藏：启动恢复 \(hiddenStates.count) 个隐藏分组")
    }

    // MARK: - 热区监听

    /// 启动全局 + 本地鼠标移动监听（仅在存在隐藏分组时运行）
    private func startMouseMonitor() {
        guard !hiddenStates.isEmpty else { return }
        guard globalMonitor == nil && localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.processMouseLocation()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.processMouseLocation()
            return event
        }
        Logger.shared.log("📍 贴边隐藏：热区监听已启动（隐藏分组数 \(hiddenStates.count)）")
    }

    private func stopMouseMonitor() {
        guard globalMonitor != nil || localMonitor != nil else {
            lastMonitorProcessTime = .distantPast
            return
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        lastMonitorProcessTime = .distantPast
        Logger.shared.log("📍 贴边隐藏：热区监听已停止")
    }

    /// 处理鼠标位置：命中唤回热区或保持显示区域时显示分组，否则滑出隐藏
    private func processMouseLocation() {
        let now = Date()
        guard now.timeIntervalSince(lastMonitorProcessTime) >= monitorThrottleInterval else { return }
        lastMonitorProcessTime = now

        guard !hiddenStates.isEmpty else {
            stopMouseMonitor()
            return
        }

        let mouseLocation = NSEvent.mouseLocation

        for (groupId, state) in hiddenStates {
            let memberWindows = state.memberIndices.compactMap { windowForButtonIndex($0) }
            guard !memberWindows.isEmpty else { continue }

            let inHotZone = isMouseInHotZone(mouseLocation, state: state)
            let inKeepVisible = isMouseInKeepVisibleArea(mouseLocation, memberWindows: memberWindows)
            let inActiveArea = inHotZone || inKeepVisible
            let revealed = isRevealed[groupId] ?? false

            // 若刚松手隐藏，正在等待用户鼠标离开边缘区域
            if isWaitingForMouseExit[groupId] == true {
                if inActiveArea {
                    // 鼠标尚未移开边缘，保持隐藏抑制唤回
                    continue
                } else {
                    // 鼠标已移开，解除抑制，之后允许主动唤回
                    isWaitingForMouseExit[groupId] = false
                    Logger.shared.log("📍 贴边隐藏：鼠标已离开边缘区域，分组唤回就绪")
                }
            }

            if inActiveArea && !revealed {
                // 唤回：整组以绝对坐标滑回屏幕内
                animateToRevealed(groupId: groupId, state: state, memberWindows: memberWindows)
                isRevealed[groupId] = true
                Logger.shared.log("📍 贴边隐藏：鼠标进入热区，分组已唤回显示")
            } else if !inActiveArea && revealed {
                // 滑出：整组以绝对坐标滑到屏幕外
                animateToHidden(groupId: groupId, state: state, memberWindows: memberWindows)
                isRevealed[groupId] = false
                Logger.shared.log("📍 贴边隐藏：鼠标离开，分组已滑出隐藏")
            }
        }
    }

    /// 鼠标是否位于分组隐藏屏幕对应边缘的唤回热区（screen.frame 的 20px 边缘条带）
    private func isMouseInHotZone(_ location: NSPoint, state: HiddenState) -> Bool {
        let frame = state.screenFrame
        switch state.edge {
        case .left:
            return location.x >= frame.minX && location.x <= frame.minX + hotZoneWidth
                && location.y >= frame.minY && location.y <= frame.maxY
        case .right:
            return location.x >= frame.maxX - hotZoneWidth && location.x <= frame.maxX
                && location.y >= frame.minY && location.y <= frame.maxY
        case .top:
            return location.y >= frame.maxY - hotZoneWidth && location.y <= frame.maxY
                && location.x >= frame.minX && location.x <= frame.maxX
        }
    }

    /// 鼠标是否位于保持显示区域：任一成员窗口 frame 外扩 8px 内，
    /// 或笔记/列表窗口可见且依附本组成员时其 frame 外扩 8px 内
    private func isMouseInKeepVisibleArea(_ location: NSPoint, memberWindows: [NSWindow]) -> Bool {
        for memberWindow in memberWindows {
            if memberWindow.frame.insetBy(dx: -keepVisibleMargin, dy: -keepVisibleMargin).contains(location) {
                return true
            }
        }
        if let note = attachedNoteWindow(for: memberWindows),
           note.frame.insetBy(dx: -keepVisibleMargin, dy: -keepVisibleMargin).contains(location) {
            return true
        }
        return false
    }

    // MARK: - 窗口绝对坐标动画

    private func animateToRevealed(groupId: UUID, state: HiddenState, memberWindows: [NSWindow]) {
        var targets: [(window: NSWindow, target: CGPoint)] = []
        for window in memberWindows {
            guard let idx = buttonIndexForWindow(window),
                  let origin = state.revealedOrigins[idx]?.cgPoint else {
                let current = window.frame.origin
                targets.append((window, CGPoint(x: current.x - state.slideOffset.width, y: current.y - state.slideOffset.height)))
                continue
            }
            targets.append((window, origin))
        }

        var noteTarget: (window: NSWindow, target: CGPoint)?
        if let note = attachedNoteWindow(for: memberWindows),
           let noteHidden = hiddenNoteOrigins[groupId] {
            noteTarget = (note, noteHidden)
        }

        animateWindows(targets: targets, noteTarget: noteTarget)
    }

    private func animateToHidden(groupId: UUID, state: HiddenState, memberWindows: [NSWindow]) {
        var targets: [(window: NSWindow, target: CGPoint)] = []
        for window in memberWindows {
            guard let idx = buttonIndexForWindow(window),
                  let origin = state.revealedOrigins[idx]?.cgPoint else {
                let current = window.frame.origin
                targets.append((window, CGPoint(x: current.x + state.slideOffset.width, y: current.y + state.slideOffset.height)))
                continue
            }
            targets.append((window, CGPoint(x: origin.x + state.slideOffset.width, y: origin.y + state.slideOffset.height)))
        }

        var noteTarget: (window: NSWindow, target: CGPoint)?
        if let note = attachedNoteWindow(for: memberWindows) {
            let currentOrigin = note.frame.origin
            hiddenNoteOrigins[groupId] = currentOrigin
            let target = CGPoint(x: currentOrigin.x + state.slideOffset.width, y: currentOrigin.y + state.slideOffset.height)
            noteTarget = (note, target)
        }

        animateWindows(targets: targets, noteTarget: noteTarget)
    }

    private func animateWindows(targets: [(window: NSWindow, target: CGPoint)], noteTarget: (window: NSWindow, target: CGPoint)?) {
        guard !targets.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            for item in targets {
                let rect = NSRect(origin: item.target, size: item.window.frame.size)
                item.window.animator().setFrame(rect, display: true)
            }
            if let noteTarget = noteTarget {
                let rect = NSRect(origin: noteTarget.target, size: noteTarget.window.frame.size)
                noteTarget.window.animator().setFrame(rect, display: true)
            }
        }
    }

    /// 笔记/列表窗口可见且依附于给定成员窗口之一时返回它
    private func attachedNoteWindow(for memberWindows: [NSWindow]) -> NSWindow? {
        guard let provider = noteWindowProvider else { return nil }
        let (note, attachedTo) = provider()
        guard let note = note, let attachedTo = attachedTo, note.isVisible else { return nil }
        return memberWindows.contains(where: { $0 === attachedTo }) ? note : nil
    }

    // MARK: - 几何计算与辅助

    /// 保存成员贴边吸附后的屏幕内正常坐标到 UserDefaults，防止被屏幕外坐标覆盖
    private func saveNormalPosition(_ position: CGPoint, for index: Int) {
        let key = "floatingButtonPosition_\(index)"
        let pointValue = NSValue(point: position)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: pointValue, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 计算把包围盒沿指定边缘完全移出屏幕所需的平移向量（仅位移对应轴，另一轴为 0）
    private func slideOutOffset(for edge: EdgeSide, union: CGRect, screenFrame: CGRect) -> CGSize {
        var offset = CGSize.zero
        switch edge {
        case .left:
            offset.width = screenFrame.minX - union.maxX
        case .right:
            offset.width = screenFrame.maxX - union.minX
        case .top:
            offset.height = screenFrame.maxY - union.minY
        }
        return offset
    }

    /// 把包围盒贴到屏幕对应边缘内侧（另一轴限制在屏幕范围内），作为唤回显示时的目标包围盒
    private func edgeRevealedRect(union: CGRect, edge: EdgeSide, screenFrame: CGRect) -> CGRect {
        var rect = union
        switch edge {
        case .left:
            rect.origin.x = screenFrame.minX
            rect.origin.y = min(max(union.minY, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - union.height))
        case .right:
            rect.origin.x = screenFrame.maxX - union.width
            rect.origin.y = min(max(union.minY, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - union.height))
        case .top:
            rect.origin.x = min(max(union.minX, screenFrame.minX), max(screenFrame.minX, screenFrame.maxX - union.width))
            rect.origin.y = screenFrame.maxY - union.height
        }
        return rect
    }

    /// 获取窗口对应的按钮索引
    private func buttonIndexForWindow(_ window: NSWindow) -> Int? {
        if let view = window.contentView as? GlowFloatingButtonView {
            return view.buttonIndex
        } else if let view = window.contentView as? FloatingButtonView {
            return view.buttonIndex
        }
        return nil
    }

    /// 按按钮索引查找悬浮球窗口
    private func windowForButtonIndex(_ index: Int) -> NSWindow? {
        for window in NSApp.windows {
            if buttonIndexForWindow(window) == index { return window }
        }
        return nil
    }

    /// 边缘中文名称（日志用）
    private func edgeDescription(_ edge: EdgeSide) -> String {
        switch edge {
        case .left: return "左"
        case .right: return "右"
        case .top: return "上"
        }
    }

    // MARK: - 持久化

    /// 持久化当前隐藏状态（UserDefaults 单键，JSON 编码 [String: HiddenState]，key = groupId.uuidString）
    private func persistHiddenStates() {
        var storage: [String: HiddenState] = [:]
        for (groupId, state) in hiddenStates {
            storage[groupId.uuidString] = state
        }
        if let data = try? JSONEncoder().encode(storage) {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else {
            Logger.shared.log("⚠️ 贴边隐藏：隐藏状态序列化失败")
        }
    }

    private func loadHiddenStates() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let storage = try? JSONDecoder().decode([String: HiddenState].self, from: data) else { return }
        var states: [UUID: HiddenState] = [:]
        for (key, state) in storage {
            guard let groupId = UUID(uuidString: key) else { continue }
            states[groupId] = state
        }
        hiddenStates = states
    }
}
