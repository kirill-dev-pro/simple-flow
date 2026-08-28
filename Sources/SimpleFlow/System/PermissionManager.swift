import AppKit
import ApplicationServices
import AVFoundation
import Foundation

public enum PermissionStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case granted
}

public protocol PermissionManaging: AnyObject, Sendable {
    var microphoneStatus: PermissionStatus { get }
    var accessibilityStatus: PermissionStatus { get }
    func requestMicrophoneAccess() async -> Bool
    func requestAccessibilityAccess() -> Bool
    func openMicrophoneSettings()
    func openAccessibilitySettings()
}

public final class PermissionManager: PermissionManaging {
    private static let microphoneSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    private static let accessibilitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    public init() {}

    public var microphoneStatus: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    public var accessibilityStatus: PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    public func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func requestAccessibilityAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openMicrophoneSettings() {
        if let url = URL(string: Self.microphoneSettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: Self.accessibilitySettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
