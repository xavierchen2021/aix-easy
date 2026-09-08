import Carbon
import CoreGraphics
import Foundation

struct HotkeyParseResult {
    let keyCode: UInt16
    let carbonModifiers: Int
    let eventFlags: CGEventFlags
}

enum HotkeyParser {
    static func parse(_ hotkeyString: String) -> HotkeyParseResult? {
        let components = hotkeyString.components(separatedBy: "+")
        guard let lastComponent = components.last?.trimmingCharacters(in: .whitespaces).uppercased() else {
            return nil
        }

        let keyMap: [String: UInt16] = [
            "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07,
            "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10,
            "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
            "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "O": 0x1F, "U": 0x20,
            "[": 0x21, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "'": 0x27, "K": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "N": 0x2D, "M": 0x2E, ".": 0x2F, "`": 0x32, "TAB": 0x30,
            "SPACE": 0x31, "DELETE": 0x33, "ENTER": 0x24, "ESC": 0x35, "UP": 0x7E, "DOWN": 0x7D, "LEFT": 0x7B, "RIGHT": 0x7C
        ]

        guard let keyCode = keyMap[lastComponent] else {
            return nil
        }

        var carbonModifiers: Int = 0
        var eventFlags: CGEventFlags = []

        for component in components.dropLast() {
            let mod = component.trimmingCharacters(in: .whitespaces).lowercased()
            switch mod {
            case "cmd", "command":
                carbonModifiers |= cmdKey
                eventFlags.insert(.maskCommand)
            case "shift":
                carbonModifiers |= shiftKey
                eventFlags.insert(.maskShift)
            case "option", "alt":
                carbonModifiers |= optionKey
                eventFlags.insert(.maskAlternate)
            case "control", "ctrl":
                carbonModifiers |= controlKey
                eventFlags.insert(.maskControl)
            default:
                break
            }
        }

        return HotkeyParseResult(
            keyCode: keyCode,
            carbonModifiers: carbonModifiers,
            eventFlags: eventFlags
        )
    }
}
