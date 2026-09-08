import Foundation
import CoreGraphics

struct DraggableState {
    var isDragging: Bool = false
    var startLocation: CGPoint = .zero
    var currentLocation: CGPoint = .zero
    
    mutating func beginDragging(at point: CGPoint) {
        isDragging = true
        startLocation = point
        currentLocation = point
    }
    
    mutating func updateDragging(to point: CGPoint) {
        guard isDragging else { return }
        currentLocation = point
    }
    
    mutating func endDragging() {
        isDragging = false
    }
}
