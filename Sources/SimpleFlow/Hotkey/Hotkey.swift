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
}
