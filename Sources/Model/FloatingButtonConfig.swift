import Foundation
import Foundation
import CoreGraphics
import AppKit

struct FloatingButtonConfig: Codable {
    var size: CGFloat
    var colorScheme: ColorScheme
    var noteWindowHeight: CGFloat
    var buttonCount: Int // 新增悬浮球数量配置
    var buttonActions: [Int: ButtonAction] // 悬浮球操作配置：索引 -> 操作
    var buttonPluginIds: [Int: String] // 悬浮球插件ID配置：索引 -> 插件ID
    var buttonHotkeys: [Int: String] // 悬浮球快捷键绑定：索引 -> 快捷键
    var clipboardHistoryLimit: Int // 剪切板历史记录数量限制
    var displayMode: DisplayMode // 显示模式：图标或文字
    var customIcons: [Int: String] // 自定义图标：索引 -> SF Symbol 名称
    var groupDisplayMode: GroupDisplayMode // 分组显示模式
    var defaultNoteGroupId: UUID? // 默认笔记分组ID
    var defaultKnowledgeGroupId: UUID? // 默认知识分组ID
    var boundWindows: [Int: BoundWindow] // 绑定的窗口信息：索引 -> 窗口信息
    var buttonCustomizations: [Int: ButtonCustomization] // 悬浮球个性化配置：索引 -> 个性化设置
    var noteOpacity: Double // 笔记透明度
    var toolbarOpacity: Double // 笔记顶部工具栏透明度
    var groupOpacity: Double // 分组透明度
    var breathingEffectOpacity: Double // 悬浮球呼吸效果透明度
    var breathingSpeed: Double // 悬浮球呼吸速度
    var enableBreathingEffect: Bool // 是否启用呼吸效果
    var clipboardSound: String // 剪切板复制提示音
    var enableClipboardSound: Bool // 是否启用剪切板复制提示音
    var glowIntensity: Double // 悬浮球发光浓度
    var toggleAIXHotkey: String // 显示/隐藏 AIX 的快捷键
    var colorPickerHotkey: String // 取色器全局快捷键
    var translationHotkey: String // 翻译全局快捷键
    var ttsEnglishVoice: String // 系统TTS 英语语音标识符
    var ttsChineseVoice: String // 系统TTS 中文语音标识符
    var ttsMode: TTSMode // TTS 引擎模式
    var edgeTtsEnglishVoice: String // Edge TTS 英语语音
    var edgeTtsChineseVoice: String // Edge TTS 中文语音
    var buttonGroups: [ButtonGroup] // 悬浮球分组
    var userHiddenButtonIndices: [Int] // 用户主动隐藏的悬浮球索引集合
    var globalHiddenState: Bool // 未被用户隐藏的悬浮球是否处于全局隐藏状态
    var aiUrl: String // AI 接口地址
    var aiApiKey: String // AI API Key
    var aiModel: String // AI 模型名称
    var aiSystemPrompt: String // AI 系统提示词
    var aiMode: AIMode // AI 模式：api 或 opencode
    var opencodeModel: String // opencode 模型名称
    var acpAutoStart: Bool // 应用启动时自动启动 ACP 服务
    var noteTheme: NoteTheme // 笔记外观主题
    var hiddenBrowsers: [String] // 隐藏的浏览器 bundleId 列表
    var browserOrder: [String] // 浏览器自定义排序 bundleId 列表
    var browserAutoClose: Bool // 选择浏览器后自动关闭窗口
    var browserAutoCloseDelay: Double // 自动关闭延迟秒数（0=立即, 3, 5, 8）
    var alwaysShowNoteActionButtons: Bool // 笔记项右侧按钮常驻显示（不隐藏）
    
    /// AI 模式枚举
    enum AIMode: String, Codable, CaseIterable {
        case api = "API"
        case opencode = "opencode"

        var localizedName: String { rawValue }
    }
    
    /// TTS 引擎模式枚举
    enum TTSMode: String, Codable, CaseIterable {
        case system = "system"   // 系统 AVSpeechSynthesizer
        case edge = "edge"       // Edge TTS 服务
        
        var displayName: String {
            switch self {
            case .system: return "系统 TTS"
            case .edge: return "Edge TTS"
            }
        }
    }
    
    // 普通初始化器
    init(size: CGFloat, colorScheme: ColorScheme, noteWindowHeight: CGFloat, buttonCount: Int,
         buttonActions: [Int: ButtonAction], buttonPluginIds: [Int: String], buttonHotkeys: [Int: String],
         clipboardHistoryLimit: Int, displayMode: DisplayMode,
         customIcons: [Int: String], groupDisplayMode: GroupDisplayMode,
         defaultNoteGroupId: UUID?, defaultKnowledgeGroupId: UUID?,
         boundWindows: [Int: BoundWindow], buttonCustomizations: [Int: ButtonCustomization],
         noteOpacity: Double, toolbarOpacity: Double, groupOpacity: Double, breathingEffectOpacity: Double,
         breathingSpeed: Double, enableBreathingEffect: Bool, clipboardSound: String, enableClipboardSound: Bool,
         glowIntensity: Double, toggleAIXHotkey: String, colorPickerHotkey: String,
         translationHotkey: String = "",
         ttsEnglishVoice: String = "",
         ttsChineseVoice: String = "",
         ttsMode: TTSMode = .system,
         edgeTtsEnglishVoice: String = "en-US-JennyNeural",
         edgeTtsChineseVoice: String = "zh-CN-XiaoxiaoNeural",
         buttonGroups: [ButtonGroup] = [],
         userHiddenButtonIndices: [Int] = [], globalHiddenState: Bool = false,
         aiUrl: String = "https://api.openai.com/v1", aiApiKey: String = "",
         aiModel: String = "gpt-4o-mini",
         aiSystemPrompt: String = "你是一个知识问答助手，请用简洁清晰的中文回答问题。",
         aiMode: AIMode = .api, opencodeModel: String = "opencode/kimi-k2.5-free",
         acpAutoStart: Bool = false,
         noteTheme: NoteTheme = .gradient,
         hiddenBrowsers: [String] = [],
         browserOrder: [String] = [],
         browserAutoClose: Bool = true,
         browserAutoCloseDelay: Double = 0,
         alwaysShowNoteActionButtons: Bool = true) {
        self.size = size
        self.colorScheme = colorScheme
        self.noteWindowHeight = noteWindowHeight
        self.buttonCount = buttonCount
        self.buttonActions = buttonActions
        self.buttonPluginIds = buttonPluginIds
        self.buttonHotkeys = buttonHotkeys
        self.clipboardHistoryLimit = clipboardHistoryLimit
        self.displayMode = displayMode
        self.customIcons = customIcons
        self.groupDisplayMode = groupDisplayMode
        self.defaultNoteGroupId = defaultNoteGroupId
        self.defaultKnowledgeGroupId = defaultKnowledgeGroupId
        self.boundWindows = boundWindows
        self.buttonCustomizations = buttonCustomizations
        self.noteOpacity = noteOpacity
        self.toolbarOpacity = toolbarOpacity
        self.groupOpacity = groupOpacity
        self.breathingEffectOpacity = breathingEffectOpacity
        self.buttonHotkeys = buttonHotkeys
        self.breathingSpeed = breathingSpeed
        self.enableBreathingEffect = enableBreathingEffect
        self.clipboardSound = clipboardSound
        self.enableClipboardSound = enableClipboardSound
        self.glowIntensity = glowIntensity
        self.toggleAIXHotkey = toggleAIXHotkey
        self.colorPickerHotkey = colorPickerHotkey
        self.translationHotkey = translationHotkey
        self.ttsEnglishVoice = ttsEnglishVoice
        self.ttsChineseVoice = ttsChineseVoice
        self.ttsMode = ttsMode
        self.edgeTtsEnglishVoice = edgeTtsEnglishVoice
        self.edgeTtsChineseVoice = edgeTtsChineseVoice
        self.buttonGroups = buttonGroups
        self.userHiddenButtonIndices = userHiddenButtonIndices
        self.globalHiddenState = globalHiddenState
        self.aiUrl = aiUrl
        self.aiApiKey = aiApiKey
        self.aiModel = aiModel
        self.aiSystemPrompt = aiSystemPrompt
        self.aiMode = aiMode
        self.opencodeModel = opencodeModel
        self.acpAutoStart = acpAutoStart
        self.noteTheme = noteTheme
        self.hiddenBrowsers = hiddenBrowsers
        self.browserOrder = browserOrder
        self.browserAutoClose = browserAutoClose
        self.browserAutoCloseDelay = browserAutoCloseDelay
        self.alwaysShowNoteActionButtons = alwaysShowNoteActionButtons
    }
    
    // 自定义解码以支持向后兼容
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decode(CGFloat.self, forKey: .size)
        colorScheme = try container.decode(ColorScheme.self, forKey: .colorScheme)
        noteWindowHeight = try container.decode(CGFloat.self, forKey: .noteWindowHeight)
        buttonCount = try container.decode(Int.self, forKey: .buttonCount)
        buttonActions = try container.decode([Int: ButtonAction].self, forKey: .buttonActions)
        buttonPluginIds = try container.decodeIfPresent([Int: String].self, forKey: .buttonPluginIds) ?? [:]
        clipboardHistoryLimit = try container.decode(Int.self, forKey: .clipboardHistoryLimit)
        displayMode = try container.decode(DisplayMode.self, forKey: .displayMode)
        customIcons = try container.decode([Int: String].self, forKey: .customIcons)
        groupDisplayMode = try container.decode(GroupDisplayMode.self, forKey: .groupDisplayMode)
        
        // 处理可能的新增字段，如果不存在则使用默认值
        defaultNoteGroupId = try container.decodeIfPresent(UUID.self, forKey: .defaultNoteGroupId) ?? NoteGroup.defaultId
        defaultKnowledgeGroupId = try container.decodeIfPresent(UUID.self, forKey: .defaultKnowledgeGroupId) ?? NoteGroup.defaultKnowledgeId
        
        boundWindows = try container.decodeIfPresent([Int: BoundWindow].self, forKey: .boundWindows) ?? [:]
        buttonCustomizations = try container.decodeIfPresent([Int: ButtonCustomization].self, forKey: .buttonCustomizations) ?? [:]
        noteOpacity = try container.decodeIfPresent(Double.self, forKey: .noteOpacity) ?? 1.0
        buttonHotkeys = try container.decodeIfPresent([Int: String].self, forKey: .buttonHotkeys) ?? [:] // 解码快捷键绑定字段
        toolbarOpacity = try container.decodeIfPresent(Double.self, forKey: .toolbarOpacity) ?? 0.9
        groupOpacity = try container.decodeIfPresent(Double.self, forKey: .groupOpacity) ?? 0.95
        breathingEffectOpacity = try container.decodeIfPresent(Double.self, forKey: .breathingEffectOpacity) ?? 0.3
        
        // 处理呼吸效果相关新增字段
        breathingSpeed = try container.decodeIfPresent(Double.self, forKey: .breathingSpeed) ?? 1.0
        enableBreathingEffect = try container.decodeIfPresent(Bool.self, forKey: .enableBreathingEffect) ?? true
        
        // 处理声音相关新增字段
        clipboardSound = try container.decodeIfPresent(String.self, forKey: .clipboardSound) ?? "Blow"
        enableClipboardSound = try container.decodeIfPresent(Bool.self, forKey: .enableClipboardSound) ?? true
        
        // 处理发光浓度新增字段
        glowIntensity = try container.decodeIfPresent(Double.self, forKey: .glowIntensity) ?? 1.0
        
        // 处理快捷键新增字段
        toggleAIXHotkey = try container.decodeIfPresent(String.self, forKey: .toggleAIXHotkey) ?? "Control+Shift+Cmd+X"
        colorPickerHotkey = try container.decodeIfPresent(String.self, forKey: .colorPickerHotkey) ?? "Cmd+Shift+P"
        translationHotkey = try container.decodeIfPresent(String.self, forKey: .translationHotkey) ?? ""
        ttsEnglishVoice = try container.decodeIfPresent(String.self, forKey: .ttsEnglishVoice) ?? ""
        ttsChineseVoice = try container.decodeIfPresent(String.self, forKey: .ttsChineseVoice) ?? ""
        ttsMode = try container.decodeIfPresent(TTSMode.self, forKey: .ttsMode) ?? .system
        edgeTtsEnglishVoice = try container.decodeIfPresent(String.self, forKey: .edgeTtsEnglishVoice) ?? "en-US-JennyNeural"
        edgeTtsChineseVoice = try container.decodeIfPresent(String.self, forKey: .edgeTtsChineseVoice) ?? "zh-CN-XiaoxiaoNeural"

        // 处理悬浮球分组新增字段
        buttonGroups = try container.decodeIfPresent([ButtonGroup].self, forKey: .buttonGroups) ?? []
        
        // 处理用户隐藏悬浮球索引新增字段
        userHiddenButtonIndices = try container.decodeIfPresent([Int].self, forKey: .userHiddenButtonIndices) ?? []
        
        // 处理全局隐藏状态新增字段
        globalHiddenState = try container.decodeIfPresent(Bool.self, forKey: .globalHiddenState) ?? false
        
        // 处理 AI 相关新增字段
        aiUrl = try container.decodeIfPresent(String.self, forKey: .aiUrl) ?? "https://api.openai.com/v1"
        aiApiKey = try container.decodeIfPresent(String.self, forKey: .aiApiKey) ?? ""
        aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel) ?? "gpt-4o-mini"
        aiSystemPrompt = try container.decodeIfPresent(String.self, forKey: .aiSystemPrompt) ?? "你是一个知识问答助手，请用简洁清晰的中文回答问题。"
        aiMode = try container.decodeIfPresent(AIMode.self, forKey: .aiMode) ?? .api
        opencodeModel = try container.decodeIfPresent(String.self, forKey: .opencodeModel) ?? "opencode/kimi-k2.5-free"
        acpAutoStart = try container.decodeIfPresent(Bool.self, forKey: .acpAutoStart) ?? false
        
        noteTheme = try container.decodeIfPresent(NoteTheme.self, forKey: .noteTheme) ?? .gradient
        
        // 浏览器相关
        hiddenBrowsers = try container.decodeIfPresent([String].self, forKey: .hiddenBrowsers) ?? []
        browserOrder = try container.decodeIfPresent([String].self, forKey: .browserOrder) ?? []
        browserAutoClose = try container.decodeIfPresent(Bool.self, forKey: .browserAutoClose) ?? true
        browserAutoCloseDelay = try container.decodeIfPresent(Double.self, forKey: .browserAutoCloseDelay) ?? 0
        alwaysShowNoteActionButtons = try container.decodeIfPresent(Bool.self, forKey: .alwaysShowNoteActionButtons) ?? true
    }
    
    struct BoundWindow: Codable {
        let windowID: UInt32
        let pid: Int32
        let appName: String
        let windowTitle: String
        let initialPosition: CGPoint? // 绑定时的窗口位置
        let initialSize: CGSize? // 绑定时的窗口大小
    }

    struct ButtonGroup: Codable, Identifiable {
        var id: UUID
        var name: String
        var memberIndices: [Int]
        var layout: GroupLayout

        init(id: UUID = UUID(), name: String = "分组", memberIndices: [Int] = [], layout: GroupLayout = .horizontal) {
            self.id = id
            self.name = name
            self.memberIndices = memberIndices
            self.layout = layout
        }
    }

    enum GroupLayout: String, Codable, CaseIterable {
        case horizontal = "水平"
        case vertical = "垂直"

        var localizedName: String {
            switch self {
            case .horizontal: return L10n.tr("config.horizontal")
            case .vertical: return L10n.tr("config.vertical")
            }
        }
    }

    struct ButtonCustomization: Codable {
        var size: CGFloat?
        var colorScheme: ColorScheme?
        var shape: ButtonShape?
        
        init(size: CGFloat? = nil, colorScheme: ColorScheme? = nil, shape: ButtonShape? = nil) {
            self.size = size
            self.colorScheme = colorScheme
            self.shape = shape
        }
    }

    enum ButtonShape: String, Codable, CaseIterable {
        case circle = "圆形"
        case roundedSquare = "圆角正方形"
        case capsule = "胶囊形"

        var localizedName: String {
            switch self {
            case .circle: return L10n.tr("config.circle")
            case .roundedSquare: return L10n.tr("config.roundedSquare")
            case .capsule: return L10n.tr("config.capsule")
            }
        }

        var cornerRadiusRatio: CGFloat {
            switch self {
            case .circle:
                return 0.5
            case .roundedSquare:
                return 0.2
            case .capsule:
                return 0.0 // 使用固定圆角
            }
        }
        
        func path(in rect: CGRect) -> CGPath {
            switch self {
            case .circle:
                let cornerRadius = min(rect.width, rect.height) * cornerRadiusRatio
                return CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            case .roundedSquare:
                let cornerRadius = min(rect.width, rect.height) * cornerRadiusRatio
                return CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            case .capsule:
                // 胶囊形状：使用高度的一半作为圆角，使左右弧形成为半圆（更圆润）
                let cornerRadius: CGFloat = rect.height / 2
                return CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            }
        }
    }

    enum DisplayMode: String, Codable, CaseIterable {
        case iconOnly = "仅图标"
        case textOnly = "仅文字"

        var localizedName: String {
            switch self {
            case .iconOnly: return L10n.tr("config.iconOnly")
            case .textOnly: return L10n.tr("config.textOnly")
            }
        }
    }

    enum GroupDisplayMode: String, Codable, CaseIterable {
        case iconOnly = "仅图标"
        case nameOnly = "仅名称"
        case both = "图标与名称"

        var localizedName: String {
            switch self {
            case .iconOnly: return L10n.tr("config.iconOnly")
            case .nameOnly: return L10n.tr("config.nameOnly")
            case .both: return L10n.tr("config.iconAndName")
            }
        }
    }

    enum ButtonAction: String, Codable, CaseIterable {
        case none = "无"
        case openNote = "打开笔记"
        case showCompletedNotes = "已完成"
        case showClipboard = "剪切板"
        case showFavorites = "常用文件"
        case toggleWindow = "控制窗口"
        case showReminder = "提醒休息"
        case colorList = "颜色列表"
        case executeHotkey = "执行快捷键"
        case showKnowledgeList = "知识列表"
        case plugin = "插件"

        var localizedName: String {
            switch self {
            case .none: return L10n.tr("common.none")
            case .openNote: return L10n.tr("config.openNote")
            case .showCompletedNotes: return L10n.tr("config.completed")
            case .showClipboard: return L10n.tr("config.clipboard")
            case .showFavorites: return L10n.tr("config.favorites")
            case .toggleWindow: return L10n.tr("config.toggleWindow")
            case .showReminder: return L10n.tr("config.breakReminder")
            case .colorList: return L10n.tr("config.colorList")
            case .executeHotkey: return L10n.tr("config.executeHotkey")
            case .showKnowledgeList: return L10n.tr("config.knowledgeList")
            case .plugin: return L10n.tr("config.plugin")
            }
        }

        var iconName: String? {
            switch self {
            case .openNote: return "note.text"
            case .showCompletedNotes: return "checkmark.circle"
            case .showClipboard: return "doc.on.clipboard"
            case .showFavorites: return "folder.fill"
            case .toggleWindow: return "eye.fill"
            case .showReminder: return "bell.fill"
            case .colorList: return "eyedropper"
            case .executeHotkey: return "keyboard"
            case .showKnowledgeList: return "books.vertical.fill"
            case .none: return nil
            case .plugin: return "puzzlepiece.extension"
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawString = try container.decode(String.self)
            self = ButtonAction(rawValue: rawString) ?? .none
        }
    }

    enum NoteTheme: String, Codable, CaseIterable {
        case solid = "纯色"
        case gradient = "质感"

        var localizedName: String {
            switch self {
            case .solid: return L10n.tr("config.solid")
            case .gradient: return L10n.tr("config.gradient")
            }
        }
    }

    enum ColorScheme: String, Codable, CaseIterable {
        case bluePurple = "蓝紫渐变"
        case pinkRose = "粉玫瑰"
        case oceanBlue = "海洋蓝"
        case sunsetOrange = "日落橙"
        case forestGreen = "森林绿"
        case pureWhite = "简约白"
        case pureBlack = "深邃黑"

        var localizedName: String {
            switch self {
            case .bluePurple: return L10n.tr("config.bluePurple")
            case .pinkRose: return L10n.tr("config.pinkRose")
            case .oceanBlue: return L10n.tr("config.oceanBlue")
            case .sunsetOrange: return L10n.tr("config.sunsetOrange")
            case .forestGreen: return L10n.tr("config.forestGreen")
            case .pureWhite: return L10n.tr("config.pureWhite")
            case .pureBlack: return L10n.tr("config.pureBlack")
            }
        }

        var startColor: CGColor {
            switch self {
            case .bluePurple:
                return CGColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
            case .pinkRose:
                return CGColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1.0)
            case .oceanBlue:
                return CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)
            case .sunsetOrange:
                return CGColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
            case .forestGreen:
                return CGColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
            case .pureWhite:
                return CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
            case .pureBlack:
                return CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            }
        }

        var endColor: CGColor {
            switch self {
            case .bluePurple:
                return CGColor(red: 0.5, green: 0.4, blue: 1.0, alpha: 1.0)
            case .pinkRose:
                return CGColor(red: 0.9, green: 0.2, blue: 0.5, alpha: 1.0)
            case .oceanBlue:
                return CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1.0)
            case .sunsetOrange:
                return CGColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1.0)
            case .forestGreen:
                return CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1.0)
            case .pureWhite:
                return CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
            case .pureBlack:
                return CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            }
        }

        var contentTintColor: CGColor {
            switch self {
            case .pureWhite:
                return CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
            default:
                return CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            }
        }
    }

    static let `default` = FloatingButtonConfig(
        size: 91,
        colorScheme: .sunsetOrange,
        noteWindowHeight: (NSScreen.main?.visibleFrame.height ?? 900) * 0.6,
        buttonCount: 3,
        buttonActions: [
            0: .openNote,
            1: .showClipboard,
            2: .showFavorites
        ],
        buttonPluginIds: [:],
        buttonHotkeys: [:],
        clipboardHistoryLimit: 50,
        displayMode: .iconOnly,
        customIcons: [:],
        groupDisplayMode: .both,
        defaultNoteGroupId: NoteGroup.defaultId,
        defaultKnowledgeGroupId: NoteGroup.defaultKnowledgeId,
        boundWindows: [:],
        buttonCustomizations: [
            0: ButtonCustomization(colorScheme: .sunsetOrange),
            1: ButtonCustomization(colorScheme: .forestGreen),
            2: ButtonCustomization(colorScheme: .oceanBlue)
        ],
        noteOpacity: 1.0,
        toolbarOpacity: 0.9,
        groupOpacity: 0.95,
        breathingEffectOpacity: 0.3,
        breathingSpeed: 1.0,
        enableBreathingEffect: true,
        clipboardSound: "Blow",
        enableClipboardSound: true,
        glowIntensity: 1.0,
        toggleAIXHotkey: "Cmd+Shift+A",
        colorPickerHotkey: "Cmd+Shift+P",
        buttonGroups: [],
        aiUrl: "https://api.openai.com/v1",
        aiApiKey: "",
        aiModel: "gpt-4o-mini",
        aiSystemPrompt: "你是一个知识问答助手，请用简洁清晰的中文回答问题。",
        aiMode: .api,
        opencodeModel: "opencode/kimi-k2.5-free",
        noteTheme: .gradient,
        hiddenBrowsers: [],
        browserOrder: [],
        browserAutoClose: true,
        browserAutoCloseDelay: 0,
        alwaysShowNoteActionButtons: true
    )
    static let minSize: CGFloat = 30
    static let maxSize: CGFloat = 150

    static let sizes: [CGFloat] = [30, 35, 40, 45, 50, 60, 70, 80, 91, 100, 120, 150]
}

@MainActor
class FloatingButtonConfigManager: ObservableObject {
    static let shared = FloatingButtonConfigManager()
    private let configKey = "floatingButtonConfig"
    private let store: SettingsStore

    @Published var config: FloatingButtonConfig

    private init() {
        self.store = AppDatabase.shared.settingsStore
        
        // Load from DB
        if let jsonString = store.loadConfig(key: configKey) {
            if let data = jsonString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(FloatingButtonConfig.self, from: data) {
                self.config = decoded
                Logger.shared.log("配置加载成功，buttonCustomizations 数量: \(decoded.buttonCustomizations.count)")
            } else {
                self.config = .default
                Logger.shared.log("配置解码失败，使用默认配置")
            }
        } else {
            self.config = .default
            Logger.shared.log("数据库中无配置记录，使用默认配置")
        }
    }

    func save() {
        saveToDB(config)
    }
    
    private func saveToDB(_ config: FloatingButtonConfig) {
        if let data = try? JSONEncoder().encode(config),
           let str = String(data: data, encoding: .utf8) {
            Logger.shared.log("准备保存配置，key=\(configKey), value长度=\(str.count)")
            do {
                try store.saveConfig(key: configKey, value: str)
                Logger.shared.log("配置保存成功，buttonCustomizations 数量: \(config.buttonCustomizations.count)")
            } catch {
                Logger.shared.log("配置保存失败: \(error.localizedDescription)")
            }
        } else {
            Logger.shared.log("配置序列化失败")
        }
    }

    func updateSize(_ size: CGFloat) {
        config.size = min(max(size, FloatingButtonConfig.minSize), FloatingButtonConfig.maxSize)
        save()
    }

    func updateColorScheme(_ scheme: FloatingButtonConfig.ColorScheme) {
        config.colorScheme = scheme
        save()
    }

    func updateNoteWindowHeight(_ height: CGFloat) {
        config.noteWindowHeight = height
        save()
    }

    func updateButtonCount(_ count: Int) {
        let oldCount = config.buttonCount
        config.buttonCount = max(1, min(count, 10)) // 支持1-10个悬浮球
        
        // 如果是新增按钮，确保新按钮不属于任何分组且不在隐藏列表中
        if config.buttonCount > oldCount {
            for i in oldCount..<config.buttonCount {
                // 遍历所有分组，移除可能存在的该索引（防止旧配置污染）
                for j in 0..<config.buttonGroups.count {
                    config.buttonGroups[j].memberIndices.removeAll { $0 == i }
                }
                // 确保新按钮不在用户隐藏列表中
                config.userHiddenButtonIndices.removeAll { $0 == i }
            }
        }
        
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateButtonAction(index: Int, action: FloatingButtonConfig.ButtonAction) {
        // 如果设置为打开笔记，确保其他按钮不是打开笔记
        if action == .openNote {
            for key in config.buttonActions.keys {
                if key != index && config.buttonActions[key] == .openNote {
                    config.buttonActions[key] = FloatingButtonConfig.ButtonAction.none
                }
            }
        }
        
        config.buttonActions[index] = action
        save()
        
        // 发送配置变更通知（用于非 SwiftUI 部分）
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateButtonPluginId(index: Int, pluginId: String?) {
        if let pluginId = pluginId, !pluginId.isEmpty {
            config.buttonPluginIds[index] = pluginId
        } else {
            config.buttonPluginIds.removeValue(forKey: index)
        }
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateClipboardHistoryLimit(_ limit: Int) {
        config.clipboardHistoryLimit = max(1, min(limit, 100))
        save()
    }

    func updateGroupDisplayMode(_ mode: FloatingButtonConfig.GroupDisplayMode) {
        config.groupDisplayMode = mode
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }
    
    func updateDefaultNoteGroupId(_ groupId: UUID?) {
        config.defaultNoteGroupId = groupId
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }
    
    func updateDefaultKnowledgeGroupId(_ groupId: UUID?) {
        config.defaultKnowledgeGroupId = groupId
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateDisplayMode(_ mode: FloatingButtonConfig.DisplayMode) {
        config.displayMode = mode
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateNoteTheme(_ theme: FloatingButtonConfig.NoteTheme) {
        config.noteTheme = theme
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateAlwaysShowNoteActionButtons(_ alwaysShow: Bool) {
        config.alwaysShowNoteActionButtons = alwaysShow
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateCustomIcon(index: Int, iconName: String) {
        if iconName.isEmpty {
            config.customIcons.removeValue(forKey: index)
        } else {
            config.customIcons[index] = iconName
        }
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func bindWindow(index: Int, windowID: UInt32, pid: Int32, appName: String, windowTitle: String, position: CGPoint?, size: CGSize?) {
        config.boundWindows[index] = FloatingButtonConfig.BoundWindow(
            windowID: windowID,
            pid: pid,
            appName: appName,
            windowTitle: windowTitle,
            initialPosition: position,
            initialSize: size
        )
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }
    
    func unbindWindow(index: Int) {
        config.boundWindows.removeValue(forKey: index)
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }
    
    func updateButtonCustomization(index: Int, customization: FloatingButtonConfig.ButtonCustomization) {
        if let group = getGroup(for: index) {
            // 如果在分组中，同步大小和形状到所有成员
            for memberIndex in group.memberIndices {
                var memberCustomization = config.buttonCustomizations[memberIndex] ?? FloatingButtonConfig.ButtonCustomization()
                memberCustomization.size = customization.size
                memberCustomization.shape = customization.shape
                if memberIndex == index {
                    // 当前球：保存用户选择的颜色
                    memberCustomization.colorScheme = customization.colorScheme
                }
                config.buttonCustomizations[memberIndex] = memberCustomization
            }
        } else {
            // 不在分组中，仅更新当前球
            config.buttonCustomizations[index] = customization
        }
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateNoteOpacity(_ opacity: Double) {
        config.noteOpacity = max(0.1, min(1.0, opacity))
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateToolbarOpacity(_ opacity: Double) {
        config.toolbarOpacity = max(0.1, min(1.0, opacity))
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateGroupOpacity(_ opacity: Double) {
        config.groupOpacity = max(0.1, min(1.0, opacity))
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateBreathingEffectOpacity(_ opacity: Double) {
        config.breathingEffectOpacity = max(0.0, min(1.0, opacity))
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }
    
    func updateBreathingSpeed(_ speed: Double) {
        config.breathingSpeed = max(0.2, min(3.0, speed))
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }
    
    func updateEnableBreathingEffect(_ enabled: Bool) {
        config.enableBreathingEffect = enabled
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }
    
    func updateClipboardSound(_ sound: String) {
        config.clipboardSound = sound
        save()
    }
    
    func updateEnableClipboardSound(_ enabled: Bool) {
        config.enableClipboardSound = enabled
        save()
    }
    
    func updateGlowIntensity(_ intensity: Double) {
        config.glowIntensity = max(0.0, min(1.0, intensity))
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }
    
    func updateToggleAIXHotkey(_ hotkey: String) {
        config.toggleAIXHotkey = hotkey
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateColorPickerHotkey(_ hotkey: String) {
        config.colorPickerHotkey = hotkey
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateTranslationHotkey(_ hotkey: String) {
        config.translationHotkey = hotkey
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func updateTTSVoice(english: String? = nil, chinese: String? = nil) {
        if let english = english {
            config.ttsEnglishVoice = english
        }
        if let chinese = chinese {
            config.ttsChineseVoice = chinese
        }
        save()
    }

    func updateTTSMode(_ mode: FloatingButtonConfig.TTSMode) {
        config.ttsMode = mode
        save()
    }

    func updateEdgeTTSVoice(english: String? = nil, chinese: String? = nil) {
        if let english = english {
            config.edgeTtsEnglishVoice = english
        }
        if let chinese = chinese {
            config.edgeTtsChineseVoice = chinese
        }
        save()
    }

    func updateButtonHotkey(index: Int, hotkey: String) {
        let trimmed = hotkey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            config.buttonHotkeys.removeValue(forKey: index)
        } else {
            config.buttonHotkeys[index] = trimmed
        }
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    func getButtonSize(index: Int) -> CGFloat {
        return config.buttonCustomizations[index]?.size ?? config.size
    }

    func getButtonColorScheme(index: Int) -> FloatingButtonConfig.ColorScheme {
        return config.buttonCustomizations[index]?.colorScheme ?? config.colorScheme
    }

    func getButtonShape(index: Int) -> FloatingButtonConfig.ButtonShape {
        return config.buttonCustomizations[index]?.shape ?? .circle
    }

    // MARK: - 悬浮球分组管理

    /// 获取指定按钮所在的分组
    func getGroup(for buttonIndex: Int) -> FloatingButtonConfig.ButtonGroup? {
        return config.buttonGroups.first { $0.memberIndices.contains(buttonIndex) }
    }

    /// 创建新分组
    func createGroup(name: String, memberIndices: [Int], layout: FloatingButtonConfig.GroupLayout = .horizontal) -> FloatingButtonConfig.ButtonGroup {
        // 先从其他分组中移除这些成员
        for index in memberIndices {
            removeFromGroup(buttonIndex: index)
        }
        let group = FloatingButtonConfig.ButtonGroup(name: name, memberIndices: memberIndices, layout: layout)
        config.buttonGroups.append(group)
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
        return group
    }

    /// 将按钮加入分组
    func addToGroup(buttonIndex: Int, groupId: UUID) {
        removeFromGroup(buttonIndex: buttonIndex)
        if let idx = config.buttonGroups.firstIndex(where: { $0.id == groupId }) {
            if !config.buttonGroups[idx].memberIndices.contains(buttonIndex) {
                config.buttonGroups[idx].memberIndices.append(buttonIndex)
            }
            save()
            NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
        }
    }

    /// 将按钮从分组中移除
    func removeFromGroup(buttonIndex: Int) {
        for i in config.buttonGroups.indices {
            config.buttonGroups[i].memberIndices.removeAll { $0 == buttonIndex }
        }
        // 清理空分组
        config.buttonGroups.removeAll { $0.memberIndices.isEmpty }
        save()
    }

    /// 更新分组布局方向
    func updateGroupLayout(groupId: UUID, layout: FloatingButtonConfig.GroupLayout) {
        if let idx = config.buttonGroups.firstIndex(where: { $0.id == groupId }) {
            config.buttonGroups[idx].layout = layout
            save()
            NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
        }
    }

    /// 删除分组
    func deleteGroup(groupId: UUID) {
        config.buttonGroups.removeAll { $0.id == groupId }
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
    }

    /// 前移/后移悬浮球在分组内的位置
    /// - Parameters:
    ///   - buttonIndex: 悬浮球全局索引
    ///   - forward: true=前移, false=后移
    /// - Returns: 是否移动成功
    @discardableResult
    func moveButtonInGroup(buttonIndex: Int, forward: Bool) -> Bool {
        guard let groupIdx = config.buttonGroups.firstIndex(where: { $0.memberIndices.contains(buttonIndex) }),
              let pos = config.buttonGroups[groupIdx].memberIndices.firstIndex(of: buttonIndex) else {
            return false
        }

        let targetPos = forward ? pos - 1 : pos + 1
        let members = config.buttonGroups[groupIdx].memberIndices
        guard targetPos >= 0 && targetPos < members.count else { return false }

        config.buttonGroups[groupIdx].memberIndices.swapAt(pos, targetPos)
        save()
        NotificationCenter.default.post(name: Notification.Name("floatingButtonConfigChanged"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("arrangeGroupMembers"), object: buttonIndex)
        return true
    }

    /// 检查悬浮球是否可以前移
    func canMoveForward(buttonIndex: Int) -> Bool {
        guard let group = getGroup(for: buttonIndex),
              let pos = group.memberIndices.firstIndex(of: buttonIndex) else { return false }
        return pos > 0
    }

    /// 检查悬浮球是否可以后移
    func canMoveBackward(buttonIndex: Int) -> Bool {
        guard let group = getGroup(for: buttonIndex),
              let pos = group.memberIndices.firstIndex(of: buttonIndex) else { return false }
        return pos < group.memberIndices.count - 1
    }

    // MARK: - 用户隐藏悬浮球管理

    /// 记录用户隐藏的悬浮球
    func recordUserHiddenButton(index: Int) {
        if !config.userHiddenButtonIndices.contains(index) {
            config.userHiddenButtonIndices.append(index)
            save()
        }
    }

    /// 移除用户隐藏记录
    func removeUserHiddenButton(index: Int) {
        config.userHiddenButtonIndices.removeAll { $0 == index }
        save()
    }

    /// 检查悬浮球是否被用户隐藏
    func isButtonHiddenByUser(index: Int) -> Bool {
        return config.userHiddenButtonIndices.contains(index)
    }

    /// 清空所有用户隐藏记录
    func clearUserHiddenButtons() {
        config.userHiddenButtonIndices.removeAll()
        save()
    }

    // MARK: - 全局隐藏状态管理

    /// 切换全局隐藏状态
    func toggleGlobalHiddenState() {
        config.globalHiddenState.toggle()
        save()
    }

    /// 设置全局隐藏状态
    func setGlobalHiddenState(_ hidden: Bool) {
        config.globalHiddenState = hidden
        save()
    }

    /// 获取全局隐藏状态
    func getGlobalHiddenState() -> Bool {
        return config.globalHiddenState
    }

    // MARK: - AI 配置管理

    /// 更新 AI 接口地址
    func updateAiUrl(_ url: String) {
        config.aiUrl = url
        save()
    }

    /// 更新 AI API Key
    func updateAiApiKey(_ key: String) {
        config.aiApiKey = key
        save()
    }

    /// 更新 AI 模型名称
    func updateAiModel(_ model: String) {
        config.aiModel = model
        save()
    }
    
    /// 更新 AI 系统提示词
    func updateAiSystemPrompt(_ prompt: String) {
        config.aiSystemPrompt = prompt
        save()
    }
    
    /// 更新 AI 模式
    func updateAiMode(_ mode: FloatingButtonConfig.AIMode) {
        config.aiMode = mode
        save()
    }
    
    /// 更新 opencode 模型名称
    func updateOpencodeModel(_ model: String) {
        config.opencodeModel = model
        save()
    }
    
    /// 更新 ACP 自动启动设置
    func updateAcpAutoStart(_ enabled: Bool) {
        config.acpAutoStart = enabled
        save()
    }
    
    /// 更新隐藏的浏览器列表
    func updateHiddenBrowsers(_ browsers: [String]) {
        config.hiddenBrowsers = browsers
        save()
    }
    
    /// 更新浏览器排序
    func updateBrowserOrder(_ order: [String]) {
        config.browserOrder = order
        save()
    }
    
    /// 更新浏览器自动关闭开关
    func updateBrowserAutoClose(_ enabled: Bool) {
        config.browserAutoClose = enabled
        save()
    }
    
    /// 更新浏览器自动关闭延迟
    func updateBrowserAutoCloseDelay(_ delay: Double) {
        config.browserAutoCloseDelay = delay
        save()
    }
}
