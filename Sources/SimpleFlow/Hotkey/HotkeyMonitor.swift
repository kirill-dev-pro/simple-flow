import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

public enum HotkeyAction: Equatable, Sendable {
    case pressed
    case released
    case cancel
}

public enum HotkeyDecision: Equatable, Sendable {
    case passThrough
    case consume
    case emit(HotkeyAction)
}

public enum HotkeyInputEvent: Equatable, Sendable {
    case flagsChanged(flags: CGEventFlags)
    case keyDown(keyCode: CGKeyCode, flags: CGEventFlags, isRepeat: Bool)
    case keyUp(keyCode: CGKeyCode, flags: CGEventFlags)
}

public struct HotkeyEventDecoder: Sendable {
    public var hotkey: Hotkey
    public private(set) var isKeyPressed: Bool

    private static let relevantModifiers: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskShift,
        .maskControl,
        .maskSecondaryFn
    ]

    public init(hotkey: Hotkey) {
        self.hotkey = hotkey
        self.isKeyPressed = false
    }

    public mutating func consume(_ event: HotkeyInputEvent, cancelEnabled: Bool) -> HotkeyDecision {
        switch event {
        case .flagsChanged(let flags):
            if hotkey.isFunctionKeyOnly {
                let hasFn = flags.contains(.maskSecondaryFn)
                if hasFn {
                    if !isKeyPressed {
                        isKeyPressed = true
                        return .emit(.pressed)
                    } else {
                        return .consume
                    }
                } else {
                    if isKeyPressed {
                        isKeyPressed = false
                        return .emit(.released)
                    } else {
                        return .passThrough
                    }
                }
            } else {
                return .passThrough
            }

        case .keyDown(let keyCode, let flags, let isRepeat):
            if cancelEnabled && keyCode == 53 {
                if isRepeat {
                    return .consume
                } else {
                    isKeyPressed = false
                    return .emit(.cancel)
                }
            }

            if !hotkey.isFunctionKeyOnly, let targetKeyCode = hotkey.keyCode, keyCode == targetKeyCode {
                if modifiersMatch(flags: flags) {
                    if isRepeat {
                        return .consume
                    } else if !isKeyPressed {
                        isKeyPressed = true
                        return .emit(.pressed)
                    } else {
                        return .consume
                    }
                } else {
                    return .passThrough
                }
            }

            return .passThrough

        case .keyUp(let keyCode, _):
            if cancelEnabled && keyCode == 53 {
                return .consume
            }

            if !hotkey.isFunctionKeyOnly, let targetKeyCode = hotkey.keyCode, keyCode == targetKeyCode {
                if isKeyPressed {
                    isKeyPressed = false
                    return .emit(.released)
                } else {
                    return .passThrough
                }
            }

            return .passThrough
        }
    }

    private func modifiersMatch(flags: CGEventFlags) -> Bool {
        let actual = flags.intersection(Self.relevantModifiers)
        let expected = CGEventFlags(rawValue: hotkey.modifiersRawValue).intersection(Self.relevantModifiers)
        return actual == expected
    }
}

public enum HotkeyMonitorError: Error, Equatable, LocalizedError, Sendable {
    case accessibilityPermissionRequired
    case tapCreationFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required to monitor global hotkeys."
        case .tapCreationFailed:
            return "Failed to create event tap."
        }
    }
}

public enum HotkeyMonitorDiagnostic {
    public static var secureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }
}

public protocol HotkeyMonitoring: AnyObject {
    func start(
        hotkey: Hotkey,
        onPress: @escaping @MainActor () -> Void,
        onRelease: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) throws
    func stop()
}

public final class HotkeyMonitor: HotkeyMonitoring {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var decoder: HotkeyEventDecoder?
    private var onPress: (@MainActor () -> Void)?
    private var onRelease: (@MainActor () -> Void)?
    private var onCancel: (@MainActor () -> Void)?
    private var isRecording: Bool = false

    public init() {}

    deinit {
        stop()
    }

    public func start(
        hotkey: Hotkey,
        onPress: @escaping @MainActor () -> Void,
        onRelease: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) throws {
        stop()

        self.decoder = HotkeyEventDecoder(hotkey: hotkey)
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
        self.isRecording = false

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let observer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            throw HotkeyMonitorError.accessibilityPermissionRequired
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        self.eventTap = tap
        self.runLoopSource = source

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        decoder = nil
        onPress = nil
        onRelease = nil
        onCancel = nil
        isRecording = false
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard var decoder = self.decoder else {
            return Unmanaged.passUnretained(event)
        }

        let inputEvent: HotkeyInputEvent
        switch type {
        case .flagsChanged:
            inputEvent = .flagsChanged(flags: event.flags)
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            inputEvent = .keyDown(keyCode: keyCode, flags: event.flags, isRepeat: isRepeat)
        case .keyUp:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            inputEvent = .keyUp(keyCode: keyCode, flags: event.flags)
        default:
            return Unmanaged.passUnretained(event)
        }

        let decision = decoder.consume(inputEvent, cancelEnabled: isRecording)
        self.decoder = decoder

        switch decision {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .consume:
            return nil
        case .emit(let action):
            switch action {
            case .pressed:
                isRecording = true
                deliver(onPress)
                return nil
            case .released:
                isRecording = false
                deliver(onRelease)
                return nil
            case .cancel:
                isRecording = false
                deliver(onCancel)
                return nil
            }
        }
    }

    private func deliver(_ callback: (@MainActor () -> Void)?) {
        guard let callback = callback else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                callback()
            }
        } else {
            DispatchQueue.main.async {
                callback()
            }
        }
    }
}
