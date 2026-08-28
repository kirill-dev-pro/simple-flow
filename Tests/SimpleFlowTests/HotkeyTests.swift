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

    func testFunctionFlagTransitionsEmitOnePressAndRelease() {
        var decoder = HotkeyEventDecoder(hotkey: .functionKey)
        XCTAssertEqual(decoder.consume(.flagsChanged(flags: [.maskSecondaryFn]), cancelEnabled: false), .emit(.pressed))
        XCTAssertEqual(decoder.consume(.flagsChanged(flags: [.maskSecondaryFn]), cancelEnabled: false), .consume)
        XCTAssertEqual(decoder.consume(.flagsChanged(flags: []), cancelEnabled: false), .emit(.released))
    }

    func testEscapeDuringRecordingEmitsCancelAndSuppressesRepeat() {
        var decoder = HotkeyEventDecoder(hotkey: .functionKey)
        XCTAssertEqual(decoder.consume(.keyDown(keyCode: 53, flags: [], isRepeat: false), cancelEnabled: true), .emit(.cancel))
        XCTAssertEqual(decoder.consume(.keyDown(keyCode: 53, flags: [], isRepeat: true), cancelEnabled: true), .consume)
        XCTAssertEqual(decoder.consume(.keyUp(keyCode: 53, flags: []), cancelEnabled: true), .consume)
    }

    func testConfiguredKeyRequiresExactModifiers() {
        let hotkey = Hotkey(keyCode: 49, modifiersRawValue: CGEventFlags.maskAlternate.rawValue, isFunctionKeyOnly: false)
        var decoder = HotkeyEventDecoder(hotkey: hotkey)
        XCTAssertEqual(decoder.consume(.keyDown(keyCode: 49, flags: [], isRepeat: false), cancelEnabled: false), .passThrough)
        XCTAssertEqual(decoder.consume(.keyDown(keyCode: 49, flags: [.maskAlternate], isRepeat: false), cancelEnabled: false), .emit(.pressed))
    }

    func testKeyRepeatDoesNotEmitSecondPress() {
        let hotkey = Hotkey(keyCode: 49, modifiersRawValue: 0, isFunctionKeyOnly: false)
        var decoder = HotkeyEventDecoder(hotkey: hotkey)
        XCTAssertEqual(decoder.consume(.keyDown(keyCode: 49, flags: [], isRepeat: false), cancelEnabled: false), .emit(.pressed))
        XCTAssertEqual(decoder.consume(.keyDown(keyCode: 49, flags: [], isRepeat: true), cancelEnabled: false), .consume)
    }

    func testCustomKeyReleaseEmitsReleased() {
        let hotkey = Hotkey(keyCode: 49, modifiersRawValue: CGEventFlags.maskAlternate.rawValue, isFunctionKeyOnly: false)
        var decoder = HotkeyEventDecoder(hotkey: hotkey)
        XCTAssertEqual(decoder.consume(.keyDown(keyCode: 49, flags: [.maskAlternate], isRepeat: false), cancelEnabled: false), .emit(.pressed))
        XCTAssertEqual(decoder.consume(.keyUp(keyCode: 49, flags: [.maskAlternate]), cancelEnabled: false), .emit(.released))
        XCTAssertEqual(decoder.consume(.keyUp(keyCode: 49, flags: [.maskAlternate]), cancelEnabled: false), .passThrough)
    }

    func testUnrelatedKeysPassThrough() {
        var decoder = HotkeyEventDecoder(hotkey: .functionKey)
        XCTAssertEqual(decoder.consume(.keyDown(keyCode: 12, flags: [], isRepeat: false), cancelEnabled: false), .passThrough)
        XCTAssertEqual(decoder.consume(.keyUp(keyCode: 12, flags: []), cancelEnabled: false), .passThrough)
        XCTAssertEqual(decoder.consume(.flagsChanged(flags: [.maskShift]), cancelEnabled: false), .passThrough)
    }

    func testEscapeWhenCancelDisabledPassesThrough() {
        var decoder = HotkeyEventDecoder(hotkey: .functionKey)
        XCTAssertEqual(decoder.consume(.keyDown(keyCode: 53, flags: [], isRepeat: false), cancelEnabled: false), .passThrough)
        XCTAssertEqual(decoder.consume(.keyUp(keyCode: 53, flags: []), cancelEnabled: false), .passThrough)
    }

    func testFlagsChangedWhileFnPressedConsumes() {
        var decoder = HotkeyEventDecoder(hotkey: .functionKey)
        XCTAssertEqual(decoder.consume(.flagsChanged(flags: [.maskSecondaryFn]), cancelEnabled: false), .emit(.pressed))
        XCTAssertEqual(decoder.consume(.flagsChanged(flags: [.maskSecondaryFn, .maskShift]), cancelEnabled: false), .consume)
        XCTAssertEqual(decoder.consume(.flagsChanged(flags: [.maskShift]), cancelEnabled: false), .emit(.released))
    }

    func testMultipleModifiersMatching() {
        let hotkey = Hotkey(
            keyCode: 49,
            modifiersRawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
            isFunctionKeyOnly: false
        )
        var decoder = HotkeyEventDecoder(hotkey: hotkey)
        XCTAssertEqual(
            decoder.consume(.keyDown(keyCode: 49, flags: [.maskCommand], isRepeat: false), cancelEnabled: false),
            .passThrough
        )
        XCTAssertEqual(
            decoder.consume(.keyDown(keyCode: 49, flags: [.maskShift], isRepeat: false), cancelEnabled: false),
            .passThrough
        )
        XCTAssertEqual(
            decoder.consume(
                .keyDown(keyCode: 49, flags: [.maskCommand, .maskShift], isRepeat: false),
                cancelEnabled: false
            ),
            .emit(.pressed)
        )
        XCTAssertEqual(
            decoder.consume(
                .keyDown(keyCode: 49, flags: [.maskCommand, .maskShift, .maskAlternate], isRepeat: false),
                cancelEnabled: false
            ),
            .passThrough
        )
    }

    func testHotkeyMonitorDiagnostic() {
        // secureInputEnabled executes without crash and returns boolean
        let isSecure = HotkeyMonitorDiagnostic.secureInputEnabled
        XCTAssertTrue(isSecure == true || isSecure == false)
    }

    func testHotkeyMonitorErrorDescriptions() {
        let permError = HotkeyMonitorError.accessibilityPermissionRequired
        XCTAssertNotNil(permError.errorDescription)
        let tapError = HotkeyMonitorError.tapCreationFailed
        XCTAssertNotNil(tapError.errorDescription)
        XCTAssertNotEqual(permError, tapError)
    }

    func testHotkeyMonitorStopIsIdempotent() {
        let monitor = HotkeyMonitor()
        monitor.stop()
        monitor.stop()
    }
}

