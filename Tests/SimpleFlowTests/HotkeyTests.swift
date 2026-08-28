import CoreGraphics
import XCTest
@testable import SimpleFlow

final class HotkeyTests: XCTestCase {
    func testFunctionKeyDefaultProperties() {
        let hotkey = Hotkey.functionKey
        XCTAssertNil(hotkey.keyCode)
        XCTAssertEqual(hotkey.modifiersRawValue, CGEventFlags.maskSecondaryFn.rawValue)
        XCTAssertTrue(hotkey.isFunctionKeyOnly)
    }

    func testFunctionKeyCodableRoundTrip() throws {
        let original = Hotkey.functionKey
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertNil(decoded.keyCode)
        XCTAssertEqual(decoded.modifiersRawValue, CGEventFlags.maskSecondaryFn.rawValue)
        XCTAssertTrue(decoded.isFunctionKeyOnly)
    }

    func testCustomCombinationCodableRoundTrip() throws {
        let original = Hotkey(
            keyCode: 49,
            modifiersRawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
            isFunctionKeyOnly: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.keyCode, 49)
        XCTAssertEqual(
            decoded.modifiersRawValue,
            CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
        )
        XCTAssertFalse(decoded.isFunctionKeyOnly)
    }

    func testEquality() {
        let fn1 = Hotkey.functionKey
        let fn2 = Hotkey(
            keyCode: nil,
            modifiersRawValue: CGEventFlags.maskSecondaryFn.rawValue,
            isFunctionKeyOnly: true
        )
        XCTAssertEqual(fn1, fn2)

        let custom1 = Hotkey(
            keyCode: 12,
            modifiersRawValue: CGEventFlags.maskControl.rawValue,
            isFunctionKeyOnly: false
        )
        let custom2 = Hotkey(
            keyCode: 13,
            modifiersRawValue: CGEventFlags.maskControl.rawValue,
            isFunctionKeyOnly: false
        )
        XCTAssertNotEqual(custom1, custom2)
        XCTAssertNotEqual(fn1, custom1)
    }
}
