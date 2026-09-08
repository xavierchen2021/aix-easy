// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AIX",
    defaultLocalization: "zh",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AIX",
            targets: ["AIX"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.2")
    ],
    targets: [
        .executableTarget(
            name: "AIX",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources",
            sources: [
                "App/FloatingButtonApp.swift",
                "App/AppDelegate.swift",
                "Model/FloatingButtonConfig.swift",
                "Model/ReminderConfig.swift",
                "Model/DraggableState.swift",
                "Model/Note.swift",
                "Model/NoteStore.swift",
                "Model/SettingsStore.swift",
                "Model/AppDatabase.swift",
                "Model/ClipboardItem.swift",
                "Model/InputMonitor.swift",
                "Model/ReminderLogger.swift",
                "Model/SmartReminderManager.swift",
                "Model/SmartReminderManager+Extensions.swift",
                "Model/FavoriteItem.swift",
                "Model/FavoriteStore.swift",
                "Model/BrowserDetector.swift",
                "Model/AutoHideManager.swift",
                "Model/BackupConfig.swift",
                "Model/BackupManager.swift",
                "Model/AIService.swift",
                "Model/AIService+Memory.swift",
                "Model/MemoryManager.swift",
                "Model/AppVersion.swift",
                "Utility/SnapManager.swift",
                "Utility/AudioActivityMonitor.swift",
                "Utility/ClipboardManager.swift",
                "Utility/TTSService.swift",
                "Utility/TTSCacheManager.swift",
                "Utility/HotkeyParser.swift",
                "Utility/HotkeyExecutor.swift",
                "Utility/SQLiteDatabase.swift",
                "Utility/IconGenerator.swift",
                "Utility/SFSymbols.swift",
                "Utility/WindowManager.swift",
                "View/TTSCacheManagerWindow.swift",
                "Utility/Logger.swift",
                "Utility/SettingsWindowManager.swift",
                "Utility/ScreenRecordingPermission.swift",
                "Utility/L10n.swift",
                "Plugin/PluginAction.swift",
                "Plugin/BasePlugin.swift",
                "Plugin/PluginManager.swift",
                "Plugin/PluginRegistry.swift",
                "Plugin/PluginConfigManager.swift",
                "Plugin/DocumentPlugins.swift",
                "Plugin/UtilityPlugins.swift",
                "Plugin/WindowManagementPlugins.swift",
                "View/FloatingWindow.swift",
                "View/FloatingButtonView.swift",
                "View/GlowFloatingButtonView.swift",
                "View/SymbolPickerView.swift",
                "View/NoteListView.swift",
                "View/NoteWindow.swift",
                "View/WelcomeWindow.swift",
                "View/LargeNoteWindow.swift",
                "View/CommonViews.swift",
                "View/AppIconView.swift",
                "View/SettingsView.swift",
                "View/PluginSettingsView.swift",
                "View/ReminderOverlayWindow.swift",
                "View/StatusBarTimerView.swift",
                "View/FavoriteListView.swift",
                "View/BrowserPickerWindow.swift",
                "View/PermissionGuideWindow.swift",
                "View/ColorListView.swift",
                "View/ColorListWindow.swift",
                "View/MemoryReviewWindows.swift",
                "View/MarkdownTheme.swift",
                "View/MermaidView.swift",
                "Model/ColorPickerManager.swift",
                "Model/TranslationManager.swift",
                "View/TranslationWindows.swift"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ]
)
