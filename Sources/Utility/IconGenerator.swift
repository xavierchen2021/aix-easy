import SwiftUI
import AppKit

@MainActor
func generateIcon() {
    let size = NSSize(width: 1024, height: 1024)
    let view = AppIconView()
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
        print("✅ Icon generated at: \(url.path)")
    } catch {
        print("❌ Failed to write icon: \(error)")
    }
}

// 由于这是一个脚本，我们需要手动调用
// generateIcon()
