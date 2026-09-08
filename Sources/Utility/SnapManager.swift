import Foundation
import Cocoa

@MainActor
struct SnapManager {
    static let shared = SnapManager()
    private let threshold: CGFloat = 20
    
    func calculateSnapPosition(for window: NSWindow) -> NSPoint {
        guard let screen = window.screen ?? NSScreen.main else {
            return window.frame.origin
        }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        var newOrigin = windowFrame.origin
        
        // 计算与各边缘的距离
        let distances: [(edge: String, distance: CGFloat, position: CGFloat)] = [
            ("left", windowFrame.minX - screenFrame.minX, screenFrame.minX),
            ("right", screenFrame.maxX - windowFrame.maxX, screenFrame.maxX - windowFrame.width),
            ("bottom", windowFrame.minY - screenFrame.minY, screenFrame.minY),
            ("top", screenFrame.maxY - windowFrame.maxY, screenFrame.maxY - windowFrame.height)
        ]
        
        // 找到最近的边缘
        let nearest = distances.min { $0.distance < $1.distance }
        
        if let nearest = nearest, nearest.distance >= 0 && nearest.distance < threshold {
            switch nearest.edge {
            case "left", "right":
                newOrigin.x = nearest.position
            case "bottom", "top":
                newOrigin.y = nearest.position
            default:
                break
            }
        }
        
        return newOrigin
    }
    
    func shouldSnap(window: NSWindow) -> Bool {
        guard let screen = window.screen ?? NSScreen.main else { return false }
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        
        let distances: [CGFloat] = [
            windowFrame.minX - screenFrame.minX,
            screenFrame.maxX - windowFrame.maxX,
            windowFrame.minY - screenFrame.minY,
            screenFrame.maxY - windowFrame.maxY
        ]
        
        return distances.contains { $0 >= 0 && $0 < threshold }
    }
}
