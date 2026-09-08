#!/bin/bash

# 悬浮按钮应用管理脚本

# 获取应用进程ID
get_app_pid() {
    # 查找 AIX 进程
    ps aux | grep "[A]IX" | awk '{print $2}'
}

# 检查应用是否正在运行
is_app_running() {
    local pid=$(get_app_pid)
    if [ -n "$pid" ]; then
        return 0
    else
        return 1
    fi
}

# 启动应用
start_app() {
    local mode=${1:-debug}
    
    # 如果是 release 模式，先检查并终止已运行的应用
    if [ "$mode" == "release" ] && is_app_running; then
        echo "⚠️  检测到应用已在运行，正在终止进程..."
        local pid=$(get_app_pid)
        kill "$pid" 2>/dev/null
        sleep 1
        # 如果还在运行，强制终止
        if is_app_running; then
            echo "🔨 强制终止进程..."
            kill -9 "$pid" 2>/dev/null
            sleep 1
        fi
        echo "✅ 已终止旧进程"
    elif is_app_running; then
        echo "✅ 应用已经在运行中"
        return 0
    fi
    
    echo "🚀 启动 AIX 应用 ($mode 模式)..."
    # 使用当前目录（工作树目录）而不是切换到主仓库
    # cd /Volumes/Cache/X
    
    if [ "$mode" == "release" ]; then
        # 编译并运行正式版
        if swift build -c release; then
            echo "📦 编译成功，正在构建应用包..."
            local app_bundle="/Applications/AIX.app"
            local contents_dir="$app_bundle/Contents"
            local macos_dir="$contents_dir/MacOS"
            local resources_dir="$contents_dir/Resources"
            
            mkdir -p "$macos_dir"
            mkdir -p "$resources_dir"
            
            # 复制二进制文件
            cp ".build/release/AIX" "$macos_dir/AIX"
            
            # 复制 SPM resource bundle (Bundle.main.bundleURL 指向 .app 根目录)
            if [ -d ".build/release/AIX_AIX.bundle" ]; then
                rm -rf "$app_bundle/AIX_AIX.bundle"
                cp -R ".build/release/AIX_AIX.bundle" "$app_bundle/AIX_AIX.bundle"
                echo "✅ 资源包已复制"
            fi
            
            # 生成图标
            echo "🎨 正在生成应用图标..."
            generate_icon
            
            # 如果图标生成成功，创建 icns 文件
            if [ -f "Sources/Resources/AppIcon.png" ]; then
                local icon_set="/tmp/AppIcon.iconset"
                mkdir -p "$icon_set"
                sips -z 16 16     Sources/Resources/AppIcon.png --out "$icon_set/icon_16x16.png" > /dev/null 2>&1
                sips -z 32 32     Sources/Resources/AppIcon.png --out "$icon_set/icon_16x16@2x.png" > /dev/null 2>&1
                sips -z 32 32     Sources/Resources/AppIcon.png --out "$icon_set/icon_32x32.png" > /dev/null 2>&1
                sips -z 64 64     Sources/Resources/AppIcon.png --out "$icon_set/icon_32x32@2x.png" > /dev/null 2>&1
                sips -z 128 128   Sources/Resources/AppIcon.png --out "$icon_set/icon_128x128.png" > /dev/null 2>&1
                sips -z 256 256   Sources/Resources/AppIcon.png --out "$icon_set/icon_128x128@2x.png" > /dev/null 2>&1
                sips -z 256 256   Sources/Resources/AppIcon.png --out "$icon_set/icon_256x256.png" > /dev/null 2>&1
                sips -z 512 512   Sources/Resources/AppIcon.png --out "$icon_set/icon_256x256@2x.png" > /dev/null 2>&1
                sips -z 512 512   Sources/Resources/AppIcon.png --out "$icon_set/icon_512x512.png" > /dev/null 2>&1
                sips -z 1024 1024 Sources/Resources/AppIcon.png --out "$icon_set/icon_512x512@2x.png" > /dev/null 2>&1
                
                iconutil -c icns "$icon_set" -o "$resources_dir/AppIcon.icns"
                rm -rf "$icon_set"
                
                # 同步更新 SPM resource bundle 中的图标
                if [ -f "$app_bundle/AIX_AIX.bundle/AppIcon.png" ]; then
                    cp "Sources/Resources/AppIcon.png" "$app_bundle/AIX_AIX.bundle/AppIcon.png"
                    echo "✅ 资源包图标已同步"
                fi
                
                echo "✅ 图标已添加"
            else
                echo "⚠️  未找到图标文件，跳过图标生成"
            fi
            
            # 复制或创建 Info.plist
            if [ -f "Info.plist" ]; then
                cp "Info.plist" "$contents_dir/Info.plist"
            else
                # 创建基本的 Info.plist
                cat <<EOF > "$contents_dir/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AIX</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.xavier.aix</string>
    <key>CFBundleName</key>
    <string>AIX</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
            fi
            
            # 进行 ad-hoc 签名 (这对辅助功能权限至关重要)
            echo "🔐 正在进行 ad-hoc 签名..."
            codesign --force --deep --sign - "$app_bundle"
            
            echo "✅ 已安装并签名到 /Applications/AIX.app"
            
            echo "🚀 启动正式版应用..."
            open "$app_bundle"
            sleep 2
        else
            echo "❌ 编译失败"
            return 1
        fi
    else
        # 编译并运行调试版
        if swift build; then
            echo "📦 编译成功，启动调试版应用..."
            # 调试版也尝试签名，否则权限可能失效
            codesign --force --deep --sign - ".build/debug/AIX"
            .build/debug/AIX > /dev/null 2>&1 &
            disown
            sleep 2
        else
            echo "❌ 编译失败"
            return 1
        fi
    fi
    
    if is_app_running; then
        echo "✅ 应用启动成功！"
        echo "📝 PID: $(get_app_pid)"
    else
        echo "❌ 应用启动失败"
        return 1
    fi
}

# 停止应用
stop_app() {
    local pid=$(get_app_pid)
    
    if [ -z "$pid" ]; then
        echo "⚠️  应用未运行"
        return 0
    fi
    
    echo "🛑 停止 AIX 应用 (PID: $pid)..."
    
    # 尝试优雅退出
    kill "$pid" 2>/dev/null
    
    # 等待进程退出
    local count=0
    while [ $count -lt 5 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "✅ 应用已停止"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    # 强制退出
    echo "⚡ 强制退出应用..."
    kill -9 "$pid" 2>/dev/null
    sleep 1
    
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "✅ 应用已强制停止"
    else
        echo "❌ 无法停止应用"
        return 1
    fi
}

# 重启应用
restart_app() {
    local mode=${1:-debug}
    echo "🔄 重启应用 ($mode 模式)..."
    stop_app
    sleep 1
    start_app "$mode"
}

# 查看应用状态
show_status() {
    local pid=$(get_app_pid)
    
    if [ -n "$pid" ]; then
        echo "✅ 应用正在运行"
        echo "📝 PID: $pid"
        echo "🕐 启动时间: $(ps -p $pid -o lstart= | xargs)"
        
        # 显示内存使用情况
        local mem_usage=$(ps -p $pid -o rss= | xargs)
        local mem_mb=$((mem_usage / 1024))
        echo "💾 内存使用: ${mem_mb} MB"
    else
        echo "❌ 应用未运行"
    fi
}

# 显示日志（如果有的话）
show_logs() {
    echo "📋 应用日志："
    echo "（应用目前输出到控制台，如需查看日志请使用 start_app 时查看输出）"
}

# 生成应用图标
generate_icon() {
    echo "🎨 正在生成应用图标..."
    
    # 创建临时生成脚本
    cat <<EOF > generate_icon_temp.swift
import SwiftUI
import AppKit

$(cat Sources/View/AppIconView.swift)

func generate() {
    let size = NSSize(width: 1024, height: 1024)
    let view = AppIconView().frame(width: 1024, height: 1024)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: size)
    
    guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        print("Failed to create bitmap rep")
        return
    }
    
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
    
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }
    
    let url = URL(fileURLWithPath: "/Volumes/Cache/X/Sources/Resources/AppIcon.png")
    do {
        try pngData.write(to: url)
        print("✅ 图标已生成: \(url.path)")
    } catch {
        print("❌ 生成失败: \(error)")
    }
}

generate()
EOF

    # 运行脚本
    swift generate_icon_temp.swift
    
    # 清理临时文件
    rm generate_icon_temp.swift
}

# 获取最新版本号
get_latest_version() {
    local dmg_files=$(ls -1 dmg/AIX_v*.dmg 2>/dev/null | grep -E 'AIX_v[0-9]+\.[0-9]+\.[0-9]+')
    
    if [ -z "$dmg_files" ]; then
        echo "1.0.0"
        return
    fi
    
    # 提取所有版本号并排序（兼容 _arm64/_x86_64 后缀）
    local latest_version=$(echo "$dmg_files" | \
        sed 's/.*AIX_v\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/' | \
        sort -t. -k1,1n -k2,2n -k3,3n -u | \
        tail -n 1)
    
    echo "$latest_version"
}

# 递增版本号（补丁版本）
increment_version() {
    local version=$1
    local major=$(echo "$version" | cut -d. -f1)
    local minor=$(echo "$version" | cut -d. -f2)
    local patch=$(echo "$version" | cut -d. -f3)
    
    # 递增补丁版本
    patch=$((patch + 1))
    
    echo "${major}.${minor}.${patch}"
}

# 构建单架构 app bundle 并生成 DMG
# 参数: arch, version, binary_path
build_arch_dmg() {
    local arch="$1"
    local version="$2"
    local binary_path="$3"
    local app_name="AIX"
    local build_dir="dist_${arch}"
    local app_bundle="$build_dir/$app_name.app"

    rm -rf "$build_dir"
    mkdir -p "$app_bundle/Contents/MacOS"
    mkdir -p "$app_bundle/Contents/Resources"

    # 复制二进制
    cp "$binary_path" "$app_bundle/Contents/MacOS/$app_name"

    # 复制 SPM resource bundle
    local bundle_dir=".build/${arch}-apple-macosx/release/AIX_AIX.bundle"
    if [ -d "$bundle_dir" ]; then
        cp -R "$bundle_dir" "$app_bundle/AIX_AIX.bundle"
    fi

    # 生成图标
    local icon_set="$build_dir/AppIcon.iconset"
    mkdir -p "$icon_set"
    sips -z 16 16     Sources/Resources/AppIcon.png --out "$icon_set/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32     Sources/Resources/AppIcon.png --out "$icon_set/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     Sources/Resources/AppIcon.png --out "$icon_set/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64     Sources/Resources/AppIcon.png --out "$icon_set/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   Sources/Resources/AppIcon.png --out "$icon_set/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256   Sources/Resources/AppIcon.png --out "$icon_set/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   Sources/Resources/AppIcon.png --out "$icon_set/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512   Sources/Resources/AppIcon.png --out "$icon_set/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   Sources/Resources/AppIcon.png --out "$icon_set/icon_512x512.png" > /dev/null 2>&1
    sips -z 1024 1024 Sources/Resources/AppIcon.png --out "$icon_set/icon_512x512@2x.png" > /dev/null 2>&1
    iconutil -c icns "$icon_set" -o "$app_bundle/Contents/Resources/AppIcon.icns"
    rm -rf "$icon_set"

    # 同步资源包图标
    if [ -f "$app_bundle/AIX_AIX.bundle/AppIcon.png" ]; then
        cp "Sources/Resources/AppIcon.png" "$app_bundle/AIX_AIX.bundle/AppIcon.png"
    fi

    # 创建 Info.plist
    if [ -f "Info.plist" ]; then
        cp "Info.plist" "$app_bundle/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_bundle/Contents/Info.plist"
    else
        cat <<EOF > "$app_bundle/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$app_name</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.xavier.aix</string>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>为了监听全局快捷键，AIX 需要获取辅助功能权限。</string>
</dict>
</plist>
EOF
    fi

    # ad-hoc 签名
    codesign --force --deep --sign - "$app_bundle"

    # 修复权限脚本
    cat <<EOF > "$build_dir/修复权限.command"
#!/bin/bash
echo "正在修复 $app_name 权限..."
sudo xattr -r -d com.apple.quarantine /Applications/$app_name.app
codesign --force --deep --sign - /Applications/$app_name.app
echo "✅ 修复完成！请重启应用，并在系统设置中授权辅助功能权限。"
EOF
    chmod +x "$build_dir/修复权限.command"

    # Applications 软链接
    ln -s /Applications "$build_dir/Applications"

    # 生成 DMG
    mkdir -p dmg
    local dmg_name="dmg/${app_name}_v${version}_${arch}.dmg"
    rm -f "$dmg_name"
    hdiutil create -volname "$app_name" -srcfolder "$build_dir" -ov -format UDZO "$dmg_name"
    rm -rf "$build_dir"
    echo "$dmg_name"
}

# 打包应用为 DMG（分架构）
package_app() {
    # 如果指定了版本号则使用，否则自动递增
    local version
    if [ -n "$1" ]; then
        version="$1"
        echo "📦 开始打包应用（手动指定版本: $version）..."
    else
        local latest_version=$(get_latest_version)
        version=$(increment_version "$latest_version")
        echo "📦 开始打包应用（从 v$latest_version 自动递增到 v$version）..."
    fi
    
    # 是否同时编译 x86_64（第二个参数为 y 时启用）
    local build_x86="$2"
    
    # 0. 更新代码中的版本号
    echo "📌 同步版本号到代码: v$version"
    sed -i '' "s/static let current = \".*\"/static let current = \"$version\"/" Sources/Model/AppVersion.swift

    # 1. 编译 arm64 版本
    echo "🔨 编译 arm64 版本..."
    if ! swift build -c release --arch arm64; then
        echo "❌ arm64 编译失败"
        return 1
    fi
    
    # 如果指定 y，额外编译 x86_64
    if [ "$build_x86" = "y" ]; then
        echo "🔨 编译 x86_64 版本..."
        if ! swift build -c release --arch x86_64; then
            echo "❌ x86_64 编译失败"
            return 1
        fi
    fi

    # 2. 生成图标（只需一次）
    echo "🎨 生成图标资源..."
    generate_icon

    # 3. 打包 arm64
    echo ""
    echo "📦 打包 arm64 DMG..."
    local arm64_dmg=$(build_arch_dmg "arm64" "$version" ".build/arm64-apple-macosx/release/AIX")
    echo "✅ $arm64_dmg"

    # 如果指定 y，打包 x86_64
    if [ "$build_x86" = "y" ]; then
        echo ""
        echo "📦 打包 x86_64 DMG..."
        local x86_dmg=$(build_arch_dmg "x86_64" "$version" ".build/x86_64-apple-macosx/release/AIX")
        echo "✅ $x86_dmg"
    fi

    echo ""
    echo "✅ 打包完成！"
    echo "📂 arm64 (Apple Silicon): $arm64_dmg"
    if [ "$build_x86" = "y" ]; then
        echo "📂 x86_64 (Intel):        $x86_dmg"
    fi
}

# 显示帮助信息
show_help() {
    echo "🔧 AIX 应用管理脚本"
    echo ""
    echo "用法: $0 [命令] [模式]"
    echo ""
    echo "命令:"
    echo "  start     启动应用 (默认 debug 模式)"
    echo "  release   启动正式版应用"
    echo "  stop      停止应用"
    echo "  restart   重启应用"
    echo "  status    查看状态"
    echo "  logs      查看日志"
    echo "  icon      生成应用图标"
    echo "  help      显示帮助"
    echo ""
    echo "模式:"
    echo "  debug     调试模式 (默认)"
    echo "  release   正式模式"
    echo ""
    echo "示例:"
    echo "  $0 start          # 启动调试版"
    echo "  $0 release        # 启动正式版"
    echo "  $0 restart debug  # 重启调试版"
    echo "  $0 stop           # 停止应用"
    echo "  $0 icon           # 生成图标"
    echo "  $0 package        # 打包应用 (默认版本, 仅 arm64)"
    echo "  $0 package 1.0.1  # 打包应用 (指定版本 1.0.1, 仅 arm64)"
    echo "  $0 package 1.0.1 y  # 打包应用 (指定版本, arm64 + x86_64)"
    echo ""
    echo "快捷方式:"
    echo "  ./manage_app.sh s  # 启动"
    echo "  ./manage_app.sh x  # 停止"
    echo "  ./manage_app.sh r  # 重启"
    echo "  ./manage_app.sh i  # 生成图标"
    echo "  ./manage_app.sh p  # 打包应用"
}

# 主逻辑
case "${1:-help}" in
    "start"|"s")
        start_app "${2:-debug}"
        ;;
    "release")
        start_app "release"
        ;;
    "stop"|"x")
        stop_app
        ;;
    "restart"|"r")
        restart_app "${2:-debug}"
        ;;
    "status"|"st")
        show_status
        ;;
    "logs"|"l")
        show_logs
        ;;
    "icon"|"i")
        generate_icon
        ;;
    "package"|"p")
        package_app "$2" "$3"
        ;;
    "help"|"h"|*)
        show_help
        ;;
esac
