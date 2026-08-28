import CoreGraphics
import Foundation

public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: CGKeyCode?
    public var modifiersRawValue: UInt64
    public var isFunctionKeyOnly: Bool

    public init(
        keyCode: CGKeyCode? = nil,
        modifiersRawValue: UInt64 = 0,
        isFunctionKeyOnly: Bool = false
    ) {
        self.keyCode = keyCode
        self.modifiersRawValue = modifiersRawValue
        self.isFunctionKeyOnly = isFunctionKeyOnly
    }

    public static let functionKey = Hotkey(
        keyCode: nil,
        modifiersRawValue: CGEventFlags.maskSecondaryFn.rawValue,
        isFunctionKeyOnly: true
    )

    public var displayString: String {
        if isFunctionKeyOnly {
            return "fn (Globe)"
        }
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiersRawValue)
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }

        if let keyCode = keyCode {
            parts.append(Self.keyString(for: keyCode))
        }
        return parts.joined(separator: " ")
    }

    private static func keyString(for keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        case 51: return "Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            return "Key(\(keyCode))"
        }
    }
}
