import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// Metadata for a completed WAV recording.
public struct RecordedAudio: Equatable, Sendable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let byteCount: Int64

    public init(fileURL: URL, duration: TimeInterval, byteCount: Int64) {
        self.fileURL = fileURL
        self.duration = duration
        self.byteCount = byteCount
    }
}

/// Typed errors for audio recording operations.
public enum AudioRecorderError: Error, Equatable, LocalizedError {
    case permissionDenied
    case deviceNotFound(String)
    case noDeviceAvailable
    case engineStartFailed(String)
    case conversionFailed(String)
    case writeFailed(String)
    case alreadyRecording
    case notRecording
    case recordingInterrupted(String)
    case invalidRecordingState(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access was denied."
        case .deviceNotFound(let uid):
            return "Microphone device '\(uid)' was not found."
        case .noDeviceAvailable:
            return "No microphone input device is available."
        case .engineStartFailed(let reason):
            return "Failed to start audio engine: \(reason)"
        case .conversionFailed(let reason):
            return "Failed to convert audio buffer: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write audio data: \(reason)"
        case .alreadyRecording:
            return "Audio recording is already in progress."
        case .notRecording:
            return "Audio recorder is not currently recording."
        case .recordingInterrupted(let reason):
            return "Audio recording was interrupted: \(reason)"
        case .invalidRecordingState(let reason):
            return "Invalid recording state: \(reason)"
        }
    }
}

/// Interface for audio recording operations.
public protocol AudioRecording: AnyObject {
    var onLimitWarning: (@Sendable () -> Void)? { get set }
    var onLimitReached: (@Sendable () -> Void)? { get set }
    var onDeviceFallback: (@Sendable (String) -> Void)? { get set }
    func start(deviceUID: String?) async throws
    func stop() async throws -> RecordedAudio
    func cancel() async
    func remove(_ recording: RecordedAudio) async
}

/// Result of selecting a CoreAudio microphone device.
public enum AudioDeviceSelectionResult: Equatable, Sendable {
    case defaultDevice
    case selectedDevice(uid: String)
    case fallbackToDefault(requestedUID: String)
}

/// Protocol for resolving and configuring input audio devices.
public protocol AudioDeviceSelecting: Sendable {
    func selectDevice(uid: String?, on audioUnit: AudioUnit?) throws -> AudioDeviceSelectionResult
}

/// Protocol for scheduling timers (injectable for instant virtual clock tests).
public protocol AudioRecorderCancellable: Sendable {
    func cancel()
}

public protocol AudioRecorderClock: Sendable {
    @discardableResult
    func schedule(after interval: TimeInterval, action: @escaping @Sendable () -> Void) -> AudioRecorderCancellable
}

/// Abstraction over AVFoundation audio capture session for deterministic unit testing.
public protocol AudioCaptureSession: AnyObject, Sendable {
    func start(
        deviceUID: String?,
        deviceSelector: AudioDeviceSelecting,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws -> AudioDeviceSelectionResult
    func stop()
}
