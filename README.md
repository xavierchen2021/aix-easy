# FloatingButton

一个现代化的macOS状态栏悬浮按钮应用。

## 功能特性

- 🚀 状态栏常驻图标
- 🎯 悬浮按钮可自由拖动
- 🧲 自动吸附到屏幕边缘
- 🎨 现代化渐变设计
- 🌙 支持深色模式

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本

## 安装方式

### 源码编译

```bash
swift build
swift run
```

### 打包为DMG

```bash
swift package generate-dmg
```

## 使用说明

1. 从状态栏图标打开悬浮按钮
2. 拖动按钮到任意位置
3. 释放按钮，自动吸附到最近边缘
4. 右键点击状态栏图标选择退出

## 项目结构

```
FloatingButton/
├── Package.swift
├── Sources/
│   ├── App/
│   │   ├── FloatingButtonApp.swift
│   │   └── AppDelegate.swift
│   ├── View/
│   │   ├── FloatingWindow.swift
│   │   └── FloatingButtonView.swift
│   ├── Model/
│   │   └── DraggableState.swift
│   └── Utility/
│       └── SnapManager.swift
└── Resources/
    └── Assets.xcassets/
```

## 技术栈

- Swift 6.0
- Swift Package Manager
- SwiftUI + AppKit 混合开发
- Core Animation
