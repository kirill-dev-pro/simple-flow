import Foundation
@preconcurrency import AVFoundation
import CoreAudio
import AudioToolbox

// MARK: - PCM16 WAV Writer

/// Writes audio buffers to a compact mono 16 kHz signed 16-bit PCM WAV file.
public final class PCM16WAVWriter: @unchecked Sendable {
    public static let standardTargetFormat: AVAudioFormat = {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("Failed to create standard 16kHz mono PCM16 AVAudioFormat")
        }
        return format
    }()

    public let url: URL
    public let targetFormat: AVAudioFormat

    private var fileHandle: FileHandle?
    private var converter: AVAudioConverter?
    private var lastInputFormat: AVAudioFormat?
    private var _totalFrames: Int64 = 0
    private let lock = NSLock()
    private var isClosed = false

    public var totalFrames: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _totalFrames
    }

    public var duration: TimeInterval {
        Double(totalFrames) / targetFormat.sampleRate
    }

    public var byteCount: Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    public init(
        url: URL,
        targetFormat: AVAudioFormat = PCM16WAVWriter.standardTargetFormat
    ) throws {
        self.url = url
        self.targetFormat = targetFormat

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        FileManager.default.createFile(atPath: url.path, contents: nil)

        do {
            let handle = try FileHandle(forWritingTo: url)
            self.fileHandle = handle
            try writeInitialHeader(handle: handle)
        } catch {
            throw AudioRecorderError.writeFailed("Failed to initialize WAV file handle at \(url.path): \(error.localizedDescription)")
        }
    }

    deinit {
        try? close()
    }

    private func writeInitialHeader(handle: FileHandle) throws {
        var header = Data()
        header.reserveCapacity(44)

        // "RIFF"
        header.append(contentsOf: "RIFF".utf8)
        var chunkSize: UInt32 = UInt32(36).littleEndian
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append(contentsOf: "WAVE".utf8)

        // "fmt "
        header.append(contentsOf: "fmt ".utf8)
        var subchunk1Size: UInt32 = UInt32(16).littleEndian
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = UInt16(1).littleEndian // PCM = 1
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels: UInt16 = UInt16(targetFormat.channelCount).littleEndian
        header.append(Data(bytes: &numChannels, count: 2))
        var sampleRate: UInt32 = UInt32(targetFormat.sampleRate).littleEndian
        header.append(Data(bytes: &sampleRate, count: 4))
        var byteRate: UInt32 = UInt32(targetFormat.sampleRate * Double(targetFormat.channelCount) * 2.0).littleEndian
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign: UInt16 = UInt16(targetFormat.channelCount * 2).littleEndian
        header.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample: UInt16 = UInt16(16).littleEndian
        header.append(Data(bytes: &bitsPerSample, count: 2))

        // "data"
        header.append(contentsOf: "data".utf8)
        var subchunk2Size: UInt32 = UInt32(0).littleEndian
        header.append(Data(bytes: &subchunk2Size, count: 4))

        handle.write(header)
    }

    public func append(_ inputBuffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed, let handle = self.fileHandle else {
            throw AudioRecorderError.writeFailed("Writer is already closed or invalid.")
        }

        guard inputBuffer.frameLength > 0 else { return }

        if inputBuffer.format == targetFormat {
            if let channelData = inputBuffer.int16ChannelData {
                let byteLength = Int(inputBuffer.frameLength) * 2
                let data = Data(bytes: channelData[0], count: byteLength)
                handle.write(data)
                _totalFrames += Int64(inputBuffer.frameLength)
            }
            return
        }

        if converter == nil || lastInputFormat != inputBuffer.format {
            guard let newConverter = AVAudioConverter(from: inputBuffer.format, to: targetFormat) else {
                throw AudioRecorderError.conversionFailed("Cannot create converter from \(inputBuffer.format) to \(targetFormat)")
            }
            newConverter.primeMethod = .normal
            self.converter = newConverter
            self.lastInputFormat = inputBuffer.format
        }

        guard let converter = self.converter else {
            throw AudioRecorderError.conversionFailed("Audio converter is unavailable")
        }

        var haveSuppliedData = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if !haveSuppliedData {
                haveSuppliedData = true
                outStatus.pointee = .haveData
                return inputBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4096) else {
                throw AudioRecorderError.conversionFailed("Failed to allocate output PCM buffer")
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
            if status == .error || conversionError != nil {
                throw AudioRecorderError.conversionFailed(
                    conversionError?.localizedDescription ?? "Conversion failed with status \(status.rawValue)"
                )
            }

            if outputBuffer.frameLength > 0, let channelData = outputBuffer.int16ChannelData {
                let byteLength = Int(outputBuffer.frameLength) * 2
                let data = Data(bytes: channelData[0], count: byteLength)
                handle.write(data)
                _totalFrames += Int64(outputBuffer.frameLength)
            }

            if status == .inputRanDry || outputBuffer.frameLength == 0 {
                break
            }
        }
    }

    public func close() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed, let handle = self.fileHandle else { return }
        isClosed = true

        if let converter = self.converter {
            while true {
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4096) else { break }
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                    outStatus.pointee = .endOfStream
                    return nil
                }
                if outputBuffer.frameLength > 0, let channelData = outputBuffer.int16ChannelData {
                    let byteLength = Int(outputBuffer.frameLength) * 2
                    let data = Data(bytes: channelData[0], count: byteLength)
                    handle.write(data)
                    _totalFrames += Int64(outputBuffer.frameLength)
                }
                if status == .endOfStream || outputBuffer.frameLength == 0 || conversionError != nil {
                    break
                }
            }
        }

        let dataSize = UInt32(_totalFrames * 2)
        let chunkSize = 36 + dataSize

        try handle.seek(toOffset: 4)
        var csFinal = chunkSize.littleEndian
        handle.write(Data(bytes: &csFinal, count: 4))

        try handle.seek(toOffset: 40)
        var dsFinal = dataSize.littleEndian
        handle.write(Data(bytes: &dsFinal, count: 4))

        try handle.synchronize()
        try handle.close()

        self.fileHandle = nil
        self.converter = nil
        self.lastInputFormat = nil
    }
}

// MARK: - CoreAudio Device Selector

public final class CoreAudioDeviceSelector: AudioDeviceSelecting, @unchecked Sendable {
    public init() {}

    public func selectDevice(uid: String?, on audioUnit: AudioUnit?) throws -> AudioDeviceSelectionResult {
        guard let uid = uid, !uid.isEmpty else {
            return .defaultDevice
        }

        guard let audioUnit = audioUnit else {
            return .fallbackToDefault(requestedUID: uid)
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var uidCF: CFString = uid as CFString
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = withUnsafeMutablePointer(to: &deviceID) { deviceIDPtr in
            withUnsafePointer(to: &uidCF) { uidCFPtr in
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    UInt32(MemoryLayout<CFString>.size),
                    uidCFPtr,
                    &size,
                    deviceIDPtr
                )
            }
        }

        if status == noErr && deviceID != kAudioObjectUnknown {
            var devID = deviceID
            let setPropertyStatus = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if setPropertyStatus == noErr {
                return .selectedDevice(uid: uid)
            }
        }

        return .fallbackToDefault(requestedUID: uid)
    }
}

// MARK: - Audio Recorder Clocks

public final class SystemAudioRecorderClock: AudioRecorderClock, @unchecked Sendable {
    public init() {}

    public func schedule(after interval: TimeInterval, action: @escaping @Sendable () -> Void) -> AudioRecorderCancellable {
        let workItem = DispatchWorkItem {
            action()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
        return WorkItemCancellable(workItem: workItem)
    }
}

private final class WorkItemCancellable: AudioRecorderCancellable, @unchecked Sendable {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}

public final class TestAudioRecorderClock: AudioRecorderClock, @unchecked Sendable {
    private struct ScheduledAction {
        let id: UUID
        let triggerTime: TimeInterval
        let action: @Sendable () -> Void
        var isCancelled: Bool
    }

    private let lock = NSLock()
    private var currentTime: TimeInterval = 0
    private var actions: [ScheduledAction] = []

    public init() {}

    public func schedule(after interval: TimeInterval, action: @escaping @Sendable () -> Void) -> AudioRecorderCancellable {
        lock.lock()
        defer { lock.unlock() }

        let id = UUID()
        let triggerTime = currentTime + interval
        let scheduled = ScheduledAction(id: id, triggerTime: triggerTime, action: action, isCancelled: false)
        actions.append(scheduled)

        return TestClockCancellable { [weak self] in
            self?.cancelAction(id: id)
        }
    }

    private func cancelAction(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if let index = actions.firstIndex(where: { $0.id == id }) {
            actions[index].isCancelled = true
        }
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        currentTime += interval

        var readyActions: [ScheduledAction] = []
        var remainingActions: [ScheduledAction] = []

        for action in actions {
            if !action.isCancelled && action.triggerTime <= currentTime {
                readyActions.append(action)
            } else if !action.isCancelled {
                remainingActions.append(action)
            }
        }

        readyActions.sort { $0.triggerTime < $1.triggerTime }
        actions = remainingActions
        lock.unlock()

        for action in readyActions {
            action.action()
        }
    }
}

private final class TestClockCancellable: AudioRecorderCancellable, @unchecked Sendable {
    private let onCancel: @Sendable () -> Void

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}

// MARK: - Capture Sessions

public final class LiveAudioCaptureSession: AudioCaptureSession, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var isRunning = false

    public init() {}

    public func start(
        deviceUID: String?,
        deviceSelector: AudioDeviceSelecting,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws -> AudioDeviceSelectionResult {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else {
            throw AudioRecorderError.alreadyRecording
        }

        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit

        let result = try deviceSelector.selectDevice(uid: deviceUID, on: audioUnit)

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.noDeviceAvailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            onBuffer(buffer)
        }

        do {
            try engine.start()
            isRunning = true
            return result
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        isRunning = false
    }
}

public final class MockAudioCaptureSession: AudioCaptureSession, @unchecked Sendable {
    public let buffersToYield: [AVAudioPCMBuffer]
    public let shouldFailOnStart: Bool
    private let lock = NSLock()
    private var isRunning = false

    public init(buffersToYield: [AVAudioPCMBuffer] = [], shouldFailOnStart: Bool = false) {
        self.buffersToYield = buffersToYield
        self.shouldFailOnStart = shouldFailOnStart
    }

    public func start(
        deviceUID: String?,
        deviceSelector: AudioDeviceSelecting,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws -> AudioDeviceSelectionResult {
        lock.lock()
        defer { lock.unlock() }

        if shouldFailOnStart {
            throw AudioRecorderError.engineStartFailed("Simulated mock audio engine start failure")
        }

        isRunning = true
        let result = try deviceSelector.selectDevice(uid: deviceUID, on: nil)

        for buffer in buffersToYield {
            onBuffer(buffer)
        }

        return result
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        isRunning = false
    }
}

public final class MockAudioDeviceSelector: AudioDeviceSelecting, @unchecked Sendable {
    public let availableUIDs: Set<String>

    public init(availableUIDs: Set<String> = []) {
        self.availableUIDs = availableUIDs
    }

    public func selectDevice(uid: String?, on audioUnit: AudioUnit?) throws -> AudioDeviceSelectionResult {
        guard let uid = uid, !uid.isEmpty else {
            return .defaultDevice
        }
        if availableUIDs.contains(uid) {
            return .selectedDevice(uid: uid)
        } else {
            return .fallbackToDefault(requestedUID: uid)
        }
    }
}

// MARK: - Audio Recorder

public final class AudioRecorder: AudioRecording, @unchecked Sendable {
    private enum State {
        case idle
        case recording
    }

    private let lock = NSLock()
    private var state: State = .idle

    private let deviceSelector: AudioDeviceSelecting
    private let clock: AudioRecorderClock
    private let captureSessionFactory: @Sendable () -> AudioCaptureSession
    private let temporaryDirectoryURL: URL
    private let writerQueue = DispatchQueue(label: "com.simpleflow.audiorecorder.writer", qos: .userInitiated)

    private var activeCaptureSession: AudioCaptureSession?
    private var activeWriter: PCM16WAVWriter?
    private var warningTimer: AudioRecorderCancellable?
    private var limitTimer: AudioRecorderCancellable?

    public var onLimitWarning: (@Sendable () -> Void)?
    public var onLimitReached: (@Sendable () -> Void)?
    public var onDeviceFallback: (@Sendable (String) -> Void)?

    private var _currentTemporaryURL: URL?
    public var currentTemporaryURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _currentTemporaryURL
    }

    public init(
        deviceSelector: AudioDeviceSelecting = CoreAudioDeviceSelector(),
        clock: AudioRecorderClock = SystemAudioRecorderClock(),
        captureSessionFactory: @escaping @Sendable () -> AudioCaptureSession = { LiveAudioCaptureSession() },
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleFlowRecordings", isDirectory: true),
        onDeviceFallback: (@Sendable (String) -> Void)? = nil
    ) {
        self.deviceSelector = deviceSelector
        self.clock = clock
        self.captureSessionFactory = captureSessionFactory
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.onDeviceFallback = onDeviceFallback
    }

    private func prepareStart(deviceUID: String?) throws -> (URL, PCM16WAVWriter, AudioCaptureSession) {
        lock.lock()
        defer { lock.unlock() }

        guard state == .idle else {
            throw AudioRecorderError.alreadyRecording
        }

        let fileURL = temporaryDirectoryURL.appendingPathComponent("recording-\(UUID().uuidString).wav")
        _currentTemporaryURL = fileURL

        let writer: PCM16WAVWriter
        do {
            writer = try PCM16WAVWriter(url: fileURL)
            self.activeWriter = writer
        } catch {
            _currentTemporaryURL = nil
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }

        let captureSession = captureSessionFactory()
        self.activeCaptureSession = captureSession
        return (fileURL, writer, captureSession)
    }

    private func finalizeStart(deviceResult: AudioDeviceSelectionResult) {
        lock.lock()
        defer { lock.unlock() }

        state = .recording

        warningTimer = clock.schedule(after: 290) { [weak self] in
            self?.onLimitWarning?()
        }

        limitTimer = clock.schedule(after: 300) { [weak self] in
            self?.onLimitReached?()
        }
    }

    private func handleStartFailure(fileURL: URL) {
        lock.lock()
        defer { lock.unlock() }

        self.activeCaptureSession = nil
        self.activeWriter = nil
        self._currentTemporaryURL = nil
        self.state = .idle
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func start(deviceUID: String?) async throws {
        let (fileURL, writer, captureSession) = try prepareStart(deviceUID: deviceUID)

        let deviceResult: AudioDeviceSelectionResult
        do {
            deviceResult = try captureSession.start(
                deviceUID: deviceUID,
                deviceSelector: deviceSelector,
                onBuffer: { [weak self, weak writer] buffer in
                    guard let self = self, let writer = writer else { return }
                    self.writerQueue.async {
                        try? writer.append(buffer)
                    }
                }
            )
        } catch {
            handleStartFailure(fileURL: fileURL)
            throw error
        }

        if case .fallbackToDefault(let requestedUID) = deviceResult {
            onDeviceFallback?(requestedUID)
        }

        finalizeStart(deviceResult: deviceResult)
    }

    private func beginStop() throws -> (URL, PCM16WAVWriter, AudioCaptureSession?) {
        lock.lock()
        defer { lock.unlock() }

        guard state == .recording, let fileURL = _currentTemporaryURL, let writer = activeWriter else {
            throw AudioRecorderError.notRecording
        }

        warningTimer?.cancel()
        warningTimer = nil
        limitTimer?.cancel()
        limitTimer = nil

        let captureSession = activeCaptureSession
        activeCaptureSession = nil
        captureSession?.stop()

        return (fileURL, writer, captureSession)
    }

    private func finishStop(fileURL: URL, success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.state = .idle
        self.activeWriter = nil
        self._currentTemporaryURL = nil
        if !success {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    public func stop() async throws -> RecordedAudio {
        let (fileURL, writer, _) = try beginStop()

        // Drain pending writer items
        await withCheckedContinuation { continuation in
            writerQueue.async {
                continuation.resume()
            }
        }

        do {
            try writer.close()
        } catch {
            finishStop(fileURL: fileURL, success: false)
            throw error
        }

        let duration = writer.duration
        let byteCount = writer.byteCount

        finishStop(fileURL: fileURL, success: true)
        return RecordedAudio(fileURL: fileURL, duration: duration, byteCount: byteCount)
    }

    private func beginCancel() -> (URL?, PCM16WAVWriter?, AudioCaptureSession?) {
        lock.lock()
        defer { lock.unlock() }

        guard state == .recording || _currentTemporaryURL != nil else {
            return (nil, nil, nil)
        }

        warningTimer?.cancel()
        warningTimer = nil
        limitTimer?.cancel()
        limitTimer = nil

        let captureSession = activeCaptureSession
        activeCaptureSession = nil
        captureSession?.stop()

        let writer = activeWriter
        activeWriter = nil
        let fileURL = _currentTemporaryURL
        _currentTemporaryURL = nil
        self.state = .idle

        return (fileURL, writer, captureSession)
    }

    public func cancel() async {
        let (fileURL, writer, _) = beginCancel()
        guard fileURL != nil || writer != nil else { return }

        await withCheckedContinuation { continuation in
            writerQueue.async {
                continuation.resume()
            }
        }

        try? writer?.close()
        if let fileURL = fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    public func remove(_ recording: RecordedAudio) async {
        if FileManager.default.fileExists(atPath: recording.fileURL.path) {
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
    }
}
