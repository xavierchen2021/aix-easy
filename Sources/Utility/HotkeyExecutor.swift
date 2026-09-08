import CoreGraphics
import Foundation

enum HotkeyExecutor {
    static func execute(hotkey: String) -> Bool {
        guard let parsed = HotkeyParser.parse(hotkey) else {
            return false
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: parsed.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: parsed.keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = parsed.eventFlags
        keyUp.flags = parsed.eventFlags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
