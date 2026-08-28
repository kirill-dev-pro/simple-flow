import XCTest
import AVFoundation
@testable import SimpleFlow

private final class TestBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

final class AudioRecorderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleFlowTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory, FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    private func temporaryURL(_ fileName: String = "\(UUID().uuidString).wav") -> URL {
        temporaryDirectory.appendingPathComponent(fileName)
    }

    private func makeStereoFloatBuffer(sampleRate: Double = 48_000, duration: TimeInterval = 1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channels = Int(format.channelCount)
        for channel in 0..<channels {
            guard let channelData = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frameCount) {
                let sample = sin(2.0 * .pi * 440.0 * Double(frame) / sampleRate)
                channelData[frame] = Float(sample * 0.5)
            }
        }
        return buffer
    }

    private func makeTargetFormatBuffer(duration: TimeInterval = 1) -> AVAudioPCMBuffer {
        let format = PCM16WAVWriter.standardTargetFormat
        let frameCount = AVAudioFrameCount(16_000 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        if let channelData = buffer.int16ChannelData {
            for frame in 0..<Int(frameCount) {
                channelData[0][frame] = Int16(frame % 1000)
            }
        }
        return buffer
    }

    private func makeRecorderWithDeterministicSource(
        duration: TimeInterval = 1,
        clock: AudioRecorderClock = TestAudioRecorderClock(),
        deviceSelector: AudioDeviceSelecting = MockAudioDeviceSelector()
    ) -> AudioRecorder {
        let buffer = makeStereoFloatBuffer(sampleRate: 48_000, duration: duration)
        let captureSession = MockAudioCaptureSession(buffersToYield: [buffer])
        return AudioRecorder(
            deviceSelector: deviceSelector,
            clock: clock,
            captureSessionFactory: { captureSession },
            temporaryDirectoryURL: temporaryDirectory
        )
    }

    // MARK: - WAV Writer Tests

    func testWriterProducesMono16kHzPCM16WAV() throws {
        let url = temporaryURL("test.wav")
        let writer = try PCM16WAVWriter(url: url)
        try writer.append(makeStereoFloatBuffer(sampleRate: 48_000, duration: 1))
        try writer.close()

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.length, 16_000, accuracy: 2)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = try XCTUnwrap(attributes[.size] as? NSNumber).int64Value
        XCTAssertLessThan(byteCount, 33_000)
        XCTAssertGreaterThan(byteCount, 32_000)
    }

    func testWriterValidatesRIFFHeader() throws {
        let url = temporaryURL("riff_test.wav")
        let writer = try PCM16WAVWriter(url: url)
        try writer.append(makeStereoFloatBuffer(sampleRate: 44_100, duration: 0.5))
        try writer.close()

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThanOrEqual(data.count, 44)
        let riffHeader = String(decoding: data.prefix(4), as: UTF8.self)
        let waveHeader = String(decoding: data[8..<12], as: UTF8.self)
        XCTAssertEqual(riffHeader, "RIFF")
        XCTAssertEqual(waveHeader, "WAVE")
    }

    func testWriterAppendsMultipleBuffersCorrectly() throws {
        let url = temporaryURL("multi_buffer.wav")
        let writer = try PCM16WAVWriter(url: url)
        try writer.append(makeStereoFloatBuffer(sampleRate: 48_000, duration: 0.5))
        try writer.append(makeStereoFloatBuffer(sampleRate: 48_000, duration: 0.5))
        try writer.close()

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.length, 16_000, accuracy: 2)
    }

    func testWriterAppendsDirectTargetFormatBuffer() throws {
        let url = temporaryURL("direct_pcm16.wav")
        let writer = try PCM16WAVWriter(url: url)
        try writer.append(makeTargetFormatBuffer(duration: 1))
        try writer.close()

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.length, 16_000)
    }

    func testWriterHandlesVariousInputSampleRates() throws {
        let sampleRates: [Double] = [22_050, 44_100, 48_000, 96_000]
        for rate in sampleRates {
            let url = temporaryURL("rate_\(Int(rate)).wav")
            let writer = try PCM16WAVWriter(url: url)
            try writer.append(makeStereoFloatBuffer(sampleRate: rate, duration: 1))
            try writer.close()

            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual(file.length, 16_000, accuracy: 5)
        }
    }

    func testWriterThrowsWhenAppendedAfterClose() throws {
        let url = temporaryURL("closed.wav")
        let writer = try PCM16WAVWriter(url: url)
        try writer.close()

        XCTAssertThrowsError(try writer.append(makeStereoFloatBuffer(sampleRate: 48_000, duration: 1))) { error in
            guard let audioError = error as? AudioRecorderError, case .writeFailed = audioError else {
                XCTFail("Expected writeFailed error, got: \(error)")
                return
            }
        }
    }

    // MARK: - Recorder Lifecycle & File Cleanup Tests

    func testCancelRemovesTemporaryFile() async throws {
        let recorder = makeRecorderWithDeterministicSource()
        try await recorder.start(deviceUID: nil)
        let url = try XCTUnwrap(recorder.currentTemporaryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        await recorder.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testStopReturnsExistingFileMetadata() async throws {
        let recorder = makeRecorderWithDeterministicSource(duration: 1)
        try await recorder.start(deviceUID: nil)
        let result = try await recorder.stop()
        XCTAssertEqual(result.duration, 1, accuracy: 0.01)
        XCTAssertGreaterThan(result.byteCount, 32_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        await recorder.remove(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.fileURL.path))
    }

    func testRemoveNonExistentFileDoesNotThrowOrCrash() async throws {
        let recorder = makeRecorderWithDeterministicSource()
        let fakeAudio = RecordedAudio(fileURL: temporaryURL("non_existent.wav"), duration: 1, byteCount: 100)
        await recorder.remove(fakeAudio)
    }

    func testStartWhenAlreadyRecordingThrows() async throws {
        let recorder = makeRecorderWithDeterministicSource()
        try await recorder.start(deviceUID: nil)
        do {
            try await recorder.start(deviceUID: nil)
            XCTFail("Expected alreadyRecording error")
        } catch let error as AudioRecorderError {
            XCTAssertEqual(error, .alreadyRecording)
        }
        await recorder.cancel()
    }

    func testStopWhenNotRecordingThrows() async throws {
        let recorder = makeRecorderWithDeterministicSource()
        do {
            _ = try await recorder.stop()
            XCTFail("Expected notRecording error")
        } catch let error as AudioRecorderError {
            XCTAssertEqual(error, .notRecording)
        }
    }

    func testStartFailureCleansUpTemporaryFile() async throws {
        let failingCaptureSession = MockAudioCaptureSession(shouldFailOnStart: true)
        let recorder = AudioRecorder(
            deviceSelector: MockAudioDeviceSelector(),
            clock: TestAudioRecorderClock(),
            captureSessionFactory: { failingCaptureSession },
            temporaryDirectoryURL: temporaryDirectory
        )

        do {
            try await recorder.start(deviceUID: nil)
            XCTFail("Expected engineStartFailed error")
        } catch let error as AudioRecorderError {
            guard case .engineStartFailed = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }

        // Check directory is empty (any created temporary file was removed)
        let contents = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        XCTAssertTrue(contents.isEmpty, "Expected temporary files to be cleaned up on start failure")
    }

    // MARK: - Limit Timers Tests

    func testWarningAndHardLimitTimersWithVirtualClock() async throws {
        let clock = TestAudioRecorderClock()
        let recorder = makeRecorderWithDeterministicSource(clock: clock)

        let warningTriggered = TestBox(false)
        let limitReachedTriggered = TestBox(false)

        recorder.onLimitWarning = {
            warningTriggered.value = true
        }
        recorder.onLimitReached = {
            limitReachedTriggered.value = true
        }

        try await recorder.start(deviceUID: nil)

        // Advance to 289s - no callbacks
        clock.advance(by: 289)
        XCTAssertFalse(warningTriggered.value)
        XCTAssertFalse(limitReachedTriggered.value)

        // Advance 1s to 290s - warning triggers
        clock.advance(by: 1)
        XCTAssertTrue(warningTriggered.value)
        XCTAssertFalse(limitReachedTriggered.value)

        // Advance 9s to 299s - limit still not triggered
        clock.advance(by: 9)
        XCTAssertFalse(limitReachedTriggered.value)

        // Advance 1s to 300s - limit triggers
        clock.advance(by: 1)
        XCTAssertTrue(limitReachedTriggered.value)

        await recorder.cancel()
    }

    func testCancelCancelsLimitTimers() async throws {
        let clock = TestAudioRecorderClock()
        let recorder = makeRecorderWithDeterministicSource(clock: clock)

        let warningTriggered = TestBox(false)
        let limitReachedTriggered = TestBox(false)

        recorder.onLimitWarning = {
            warningTriggered.value = true
        }
        recorder.onLimitReached = {
            limitReachedTriggered.value = true
        }

        try await recorder.start(deviceUID: nil)
        clock.advance(by: 100)
        await recorder.cancel()

        // Advance past 300s
        clock.advance(by: 300)
        XCTAssertFalse(warningTriggered.value)
        XCTAssertFalse(limitReachedTriggered.value)
    }

    func testStopCancelsLimitTimers() async throws {
        let clock = TestAudioRecorderClock()
        let recorder = makeRecorderWithDeterministicSource(clock: clock)

        let warningTriggered = TestBox(false)
        let limitReachedTriggered = TestBox(false)

        recorder.onLimitWarning = {
            warningTriggered.value = true
        }
        recorder.onLimitReached = {
            limitReachedTriggered.value = true
        }

        try await recorder.start(deviceUID: nil)
        let recording = try await recorder.stop()
        await recorder.remove(recording)

        clock.advance(by: 350)
        XCTAssertFalse(warningTriggered.value)
        XCTAssertFalse(limitReachedTriggered.value)
    }

    // MARK: - Device Selection Fallback Tests

    func testDeviceSelectionFallbackNotifiesFallback() async throws {
        let selector = MockAudioDeviceSelector(availableUIDs: ["valid-mic-uid"])
        let fallbackReportedUID = TestBox<String?>(nil)

        let recorder = AudioRecorder(
            deviceSelector: selector,
            clock: TestAudioRecorderClock(),
            captureSessionFactory: { MockAudioCaptureSession(buffersToYield: []) },
            temporaryDirectoryURL: temporaryDirectory,
            onDeviceFallback: { requestedUID in
                fallbackReportedUID.value = requestedUID
            }
        )

        try await recorder.start(deviceUID: "disconnected-mic-uid")
        XCTAssertEqual(fallbackReportedUID.value, "disconnected-mic-uid")
        await recorder.cancel()
    }

    func testDeviceSelectionValidUIDDoesNotFallback() async throws {
        let selector = MockAudioDeviceSelector(availableUIDs: ["valid-mic-uid"])
        let fallbackReportedUID = TestBox<String?>(nil)

        let recorder = AudioRecorder(
            deviceSelector: selector,
            clock: TestAudioRecorderClock(),
            captureSessionFactory: { MockAudioCaptureSession(buffersToYield: []) },
            temporaryDirectoryURL: temporaryDirectory,
            onDeviceFallback: { requestedUID in
                fallbackReportedUID.value = requestedUID
            }
        )

        try await recorder.start(deviceUID: "valid-mic-uid")
        XCTAssertNil(fallbackReportedUID.value)
        await recorder.cancel()
    }

    // MARK: - Abandoned Recordings Cleanup Tests

    func testCleanupAbandonedRecordingsRemovesOnlyOldWAVFiles() throws {
        let dedicatedDir = temporaryDirectory.appendingPathComponent("DedicatedRecordings", isDirectory: true)
        let outsideDir = temporaryDirectory.appendingPathComponent("OutsideDir", isDirectory: true)
        try FileManager.default.createDirectory(at: dedicatedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)

        let oldDate = Date().addingTimeInterval(-3700)
        let newDate = Date().addingTimeInterval(-60)

        let oldWavURL = dedicatedDir.appendingPathComponent("recording-old.wav")
        let newWavURL = dedicatedDir.appendingPathComponent("recording-new.wav")
        let oldTxtURL = dedicatedDir.appendingPathComponent("notes-old.txt")
        let outsideOldWavURL = outsideDir.appendingPathComponent("recording-outside-old.wav")

        FileManager.default.createFile(atPath: oldWavURL.path, contents: Data([0x01, 0x02]))
        try FileManager.default.setAttributes([.creationDate: oldDate, .modificationDate: oldDate], ofItemAtPath: oldWavURL.path)

        FileManager.default.createFile(atPath: newWavURL.path, contents: Data([0x03, 0x04]))
        try FileManager.default.setAttributes([.creationDate: newDate, .modificationDate: newDate], ofItemAtPath: newWavURL.path)

        FileManager.default.createFile(atPath: oldTxtURL.path, contents: Data([0x05, 0x06]))
        try FileManager.default.setAttributes([.creationDate: oldDate, .modificationDate: oldDate], ofItemAtPath: oldTxtURL.path)

        FileManager.default.createFile(atPath: outsideOldWavURL.path, contents: Data([0x07, 0x08]))
        try FileManager.default.setAttributes([.creationDate: oldDate, .modificationDate: oldDate], ofItemAtPath: outsideOldWavURL.path)

        let deletedCount = AudioRecorder.cleanupAbandonedRecordings(in: dedicatedDir, olderThan: 3600)

        XCTAssertEqual(deletedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldWavURL.path), "Old WAV file in dedicated directory should be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newWavURL.path), "New WAV file in dedicated directory should be kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldTxtURL.path), "Non-WAV file should be kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideOldWavURL.path), "Old WAV file outside dedicated directory should be kept")
    }

    func testCleanupAbandonedRecordingsWhenDirectoryDoesNotExistDoesNotThrow() {
        let nonExistentDir = temporaryDirectory.appendingPathComponent("NonExistentDir_\(UUID().uuidString)")
        let deletedCount = AudioRecorder.cleanupAbandonedRecordings(in: nonExistentDir, olderThan: 3600)
        XCTAssertEqual(deletedCount, 0)
    }
}
