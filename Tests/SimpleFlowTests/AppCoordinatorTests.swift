import ApplicationServices
import Foundation
import XCTest
@testable import SimpleFlow

// MARK: - Test Helpers & Fakes

enum HarnessCall: Equatable {
    case captureFocus
    case startAudio
    case stopAudio
    case cancelAudio
    case removeAudio
    case transcribe
    case saveHistory(status: InsertionStatus)
    case updateHistory(status: InsertionStatus)
    case insert
}

final class CallsTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [HarnessCall] = []

    var calls: [HarnessCall] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    func record(_ call: HarnessCall) {
        lock.lock()
        defer { lock.unlock() }
        _calls.append(call)
    }
}

final class FakeAudioRecorder: AudioRecording, @unchecked Sendable {
    private let tracker: CallsTracker
    var onLimitWarning: (@Sendable () -> Void)?
    var onLimitReached: (@Sendable () -> Void)?

    var startAudioCallCount = 0
    var stopAudioCallCount = 0
    var cancelAudioCallCount = 0
    var removeAudioCallCount = 0
    var shouldFailOnStart = false
    var shouldFailOnStop = false

    init(tracker: CallsTracker) {
        self.tracker = tracker
    }

    func start(deviceUID: String?) async throws {
        if shouldFailOnStart {
            throw AudioRecorderError.permissionDenied
        }
        startAudioCallCount += 1
        tracker.record(.startAudio)
    }

    func stop() async throws -> RecordedAudio {
        if shouldFailOnStop {
            throw AudioRecorderError.notRecording
        }
        stopAudioCallCount += 1
        tracker.record(.stopAudio)
        return RecordedAudio(
            fileURL: URL(fileURLWithPath: "/tmp/fake-recording-\(UUID().uuidString).wav"),
            duration: 2.0,
            byteCount: 64000
        )
    }

    func cancel() async {
        cancelAudioCallCount += 1
        tracker.record(.cancelAudio)
    }

    func remove(_ recording: RecordedAudio) async {
        removeAudioCallCount += 1
        tracker.record(.removeAudio)
    }
}

final class FakeFocusTracker: FocusTracking, @unchecked Sendable {
    private let tracker: CallsTracker
    var focusToReturn: FocusSnapshot?
    var focusStillMatches: Bool

    init(tracker: CallsTracker, focusStillMatches: Bool = true) {
        self.tracker = tracker
        self.focusStillMatches = focusStillMatches
        self.focusToReturn = FocusSnapshot(
            applicationPID: 9999,
            applicationName: "TextEdit",
            element: AXUIElementCreateSystemWide()
        )
    }

    func capture() -> FocusSnapshot? {
        tracker.record(.captureFocus)
        return focusToReturn
    }

    func stillMatches(_ snapshot: FocusSnapshot) -> Bool {
        focusStillMatches
    }
}

final class FakeTranscriber: Transcribing, @unchecked Sendable {
    private let tracker: CallsTracker
    var result: Result<String, TranscriptionError>
    private(set) var transcribeCallCount = 0
    private var suspendContinuation: CheckedContinuation<Void, Never>?
    private var isSuspended: Bool
    private var isResumed: Bool = false
    private let lock = NSLock()

    init(tracker: CallsTracker, result: Result<String, TranscriptionError>, isSuspended: Bool = false) {
        self.tracker = tracker
        self.result = result
        self.isSuspended = isSuspended
    }

    private func recordAndCheckSuspend() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        transcribeCallCount += 1
        tracker.record(.transcribe)
        return isSuspended && !isResumed
    }

    private func registerContinuationOrResumeImmediately(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isResumed {
            return true
        } else {
            self.suspendContinuation = continuation
            return false
        }
    }

    func transcribe(fileURL: URL, configuration: TranscriptionConfiguration) async throws -> String {
        let needsSuspend = recordAndCheckSuspend()

        if needsSuspend {
            await withCheckedContinuation { continuation in
                if registerContinuationOrResumeImmediately(continuation) {
                    continuation.resume()
                }
            }
        }

        switch result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }

    func resume() {
        lock.lock()
        isResumed = true
        let continuation = suspendContinuation
        suspendContinuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

final class FakeHistoryRepository: HistoryStoring, @unchecked Sendable {
    private let tracker: CallsTracker
    private let lock = NSLock()
    private var _savedRecords: [TranscriptRecord] = []

    var savedRecords: [TranscriptRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _savedRecords
    }

    init(tracker: CallsTracker) {
        self.tracker = tracker
    }

    func save(
        text: String,
        createdAt: Date,
        sourceApplicationName: String?,
        insertionStatus: InsertionStatus
    ) throws -> TranscriptRecord {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HistoryError.emptyText
        }

        let record = TranscriptRecord(
            text: text,
            createdAt: createdAt,
            sourceApplicationName: sourceApplicationName,
            insertionStatus: insertionStatus
        )
        lock.lock()
        _savedRecords.append(record)
        lock.unlock()

        tracker.record(.saveHistory(status: insertionStatus))
        return record
    }

    func updateInsertionStatus(_ record: TranscriptRecord, to status: InsertionStatus) throws {
        record.insertionStatus = status
        tracker.record(.updateHistory(status: status))
    }

    func fetchAll() throws -> [TranscriptRecord] {
        savedRecords
    }

    func delete(_ record: TranscriptRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        _savedRecords.removeAll(where: { $0.id == record.id })
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        _savedRecords.removeAll()
    }
}

final class FakeTextInserter: TextInserting, @unchecked Sendable {
    private let tracker: CallsTracker
    var result: InsertionResult
    var insertCallCount = 0

    init(tracker: CallsTracker, result: InsertionResult = .inserted) {
        self.tracker = tracker
        self.result = result
    }

    func insert(_ text: String) async -> InsertionResult {
        insertCallCount += 1
        tracker.record(.insert)
        return result
    }
}

final class FakeHUD: HUDPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var _presentedPhases: [DictationPhase] = []
    var limitWarningCount = 0
    var hideCallCount = 0

    var presentedPhases: [DictationPhase] {
        lock.lock()
        defer { lock.unlock() }
        return _presentedPhases
    }

    @MainActor
    func show(_ phase: DictationPhase) {
        lock.lock()
        _presentedPhases.append(phase)
        lock.unlock()
    }

    @MainActor
    func showLimitWarning() {
        limitWarningCount += 1
    }

    @MainActor
    func hide() {
        hideCallCount += 1
    }
}

final class FakeHotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    var onPress: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var isStarted = false

    func start(
        hotkey: Hotkey,
        onPress: @escaping @MainActor () -> Void,
        onRelease: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) throws {
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
        self.isStarted = true
    }

    func stop() {
        self.isStarted = false
        self.onPress = nil
        self.onRelease = nil
        self.onCancel = nil
    }
}

extension Collection {
    var single: Element? {
        count == 1 ? first : nil
    }
}

// MARK: - Coordinator Harness

@MainActor
final class CoordinatorHarness {
    let callsTracker: CallsTracker
    let fakeRecorder: FakeAudioRecorder
    let fakeTranscriber: FakeTranscriber
    let fakeFocusTracker: FakeFocusTracker
    let fakeHistoryRepository: FakeHistoryRepository
    let fakeInserter: FakeTextInserter
    let fakeHUD: FakeHUD
    let fakeHotkeyMonitor: FakeHotkeyMonitor
    let settingsStore: SettingsStore
    let coordinator: AppCoordinator

    var calls: [HarnessCall] { callsTracker.calls }
    var inserterWasCalled: Bool { fakeInserter.insertCallCount > 0 }
    var savedStatus: InsertionStatus? { fakeHistoryRepository.savedRecords.first?.insertionStatus }
    var removeAudioCallCount: Int { fakeRecorder.removeAudioCallCount }
    var cancelAudioCallCount: Int { fakeRecorder.cancelAudioCallCount }
    var startAudioCallCount: Int { fakeRecorder.startAudioCallCount }
    var transcribeCallCount: Int { fakeTranscriber.transcribeCallCount }
    var savedRecords: [TranscriptRecord] { fakeHistoryRepository.savedRecords }

    var presentedFeedback: FeedbackKind? {
        for phase in fakeHUD.presentedPhases.reversed() {
            if case .feedback(let kind) = phase {
                return kind
            }
        }
        return nil
    }

    init(
        transcript: String = "hello",
        transcriptionResult: Result<String, TranscriptionError>? = nil,
        focusStillMatches: Bool = true,
        insertionResult: InsertionResult = .inserted,
        suspendedTranscription: Bool = false
    ) {
        let tracker = CallsTracker()
        self.callsTracker = tracker
        self.fakeRecorder = FakeAudioRecorder(tracker: tracker)
        self.fakeFocusTracker = FakeFocusTracker(tracker: tracker, focusStillMatches: focusStillMatches)
        self.fakeTranscriber = FakeTranscriber(
            tracker: tracker,
            result: transcriptionResult ?? .success(transcript),
            isSuspended: suspendedTranscription
        )
        self.fakeHistoryRepository = FakeHistoryRepository(tracker: tracker)
        self.fakeInserter = FakeTextInserter(tracker: tracker, result: insertionResult)
        self.fakeHUD = FakeHUD()
        self.fakeHotkeyMonitor = FakeHotkeyMonitor()

        let userDefaults = UserDefaults(suiteName: "dev.kirill.simpleflow.harness.\(UUID().uuidString)")!
        let tokenStore = InMemoryTokenStore(initialToken: "test-token")
        self.settingsStore = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)
        self.settingsStore.baseURL = "https://api.openai.com/v1"
        self.settingsStore.model = "whisper-1"

        self.coordinator = AppCoordinator(
            hotkeyMonitor: fakeHotkeyMonitor,
            audioRecorder: fakeRecorder,
            focusTracker: fakeFocusTracker,
            transcriptionClient: fakeTranscriber,
            textInserter: fakeInserter,
            historyRepository: fakeHistoryRepository,
            settingsStore: settingsStore,
            hudPresenter: fakeHUD
        )
        self.coordinator.start()
    }

    static func withSuspendedTranscription() -> CoordinatorHarness {
        CoordinatorHarness(suspendedTranscription: true)
    }

    func press() async {
        fakeHotkeyMonitor.onPress?()
        // Allow any immediate async start work to cycle
        await Task.yield()
    }

    func release() async {
        fakeHotkeyMonitor.onRelease?()
    }

    func pressAndRelease() async {
        await press()
        await release()
    }

    func waitUntilTranscribing() async {
        while true {
            if fakeTranscriber.transcribeCallCount > 0 {
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func pressReleaseAndComplete() async {
        await press()
        await release()
        await coordinator.waitForDictationCompletion()
    }

    func pressThenEscape() async {
        await press()
        fakeHotkeyMonitor.onCancel?()
        await coordinator.waitForDictationCompletion()
    }

    func resumeTranscription() {
        fakeTranscriber.resume()
    }
}

// MARK: - AppCoordinator Tests

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testSuccessfulTranscriptIsSavedBeforeInsertion() async throws {
        let harness = CoordinatorHarness(transcript: "hello", focusStillMatches: true)
        await harness.pressReleaseAndComplete()
        XCTAssertEqual(harness.calls, [
            .captureFocus, .startAudio, .stopAudio, .transcribe,
            .saveHistory(status: .pasteFailed), .insert,
            .updateHistory(status: .inserted), .removeAudio
        ])
        XCTAssertEqual(harness.presentedFeedback, .inserted)
    }

    func testChangedFocusSavesWithoutInsertion() async throws {
        let harness = CoordinatorHarness(transcript: "hello", focusStillMatches: false)
        await harness.pressReleaseAndComplete()
        XCTAssertFalse(harness.inserterWasCalled)
        XCTAssertEqual(harness.savedStatus, .focusChanged)
        XCTAssertEqual(harness.presentedFeedback, .savedToHistory)
        XCTAssertEqual(harness.calls, [
            .captureFocus, .startAudio, .stopAudio, .transcribe,
            .saveHistory(status: .focusChanged), .removeAudio
        ])
    }

    func testAPIFailureDeletesAudioAndCreatesNoHistory() async {
        let harness = CoordinatorHarness(transcriptionResult: .failure(.transport(.notConnectedToInternet)))
        await harness.pressReleaseAndComplete()
        XCTAssertEqual(harness.removeAudioCallCount, 1)
        XCTAssertTrue(harness.savedRecords.isEmpty)
        XCTAssertEqual(harness.presentedFeedback, .error("No internet connection"))
    }

    func testEscapeCancelsWithoutAPIOrHistory() async {
        let harness = CoordinatorHarness(transcript: "unused")
        await harness.pressThenEscape()
        XCTAssertEqual(harness.cancelAudioCallCount, 1)
        XCTAssertEqual(harness.transcribeCallCount, 0)
        XCTAssertTrue(harness.savedRecords.isEmpty)
    }

    func testSecondPressWhileTranscribingIsIgnored() async {
        let harness = CoordinatorHarness.withSuspendedTranscription()
        await harness.pressAndRelease()
        await harness.waitUntilTranscribing()
        await harness.press()
        XCTAssertEqual(harness.startAudioCallCount, 1)
        harness.resumeTranscription()
        await harness.coordinator.waitForDictationCompletion()
    }

    func testPasteFailureKeepsProvisionalPasteFailedStatus() async {
        let harness = CoordinatorHarness(transcript: "hello", focusStillMatches: true, insertionResult: .pasteFailed)
        await harness.pressReleaseAndComplete()
        XCTAssertEqual(harness.savedRecords.single?.insertionStatus, .pasteFailed)
        XCTAssertEqual(harness.presentedFeedback, .savedToHistory)
    }

    func testLimitReachedTriggersStopAndTranscribe() async {
        let harness = CoordinatorHarness(transcript: "limit reached text", focusStillMatches: true)
        await harness.press()
        harness.fakeRecorder.onLimitReached?()
        await harness.coordinator.waitForDictationCompletion()
        XCTAssertEqual(harness.savedRecords.single?.text, "limit reached text")
        XCTAssertEqual(harness.presentedFeedback, .inserted)
    }

    func testLimitWarningNotifiesHUD() async {
        let harness = CoordinatorHarness(transcript: "limit warning test")
        await harness.press()
        harness.fakeRecorder.onLimitWarning?()
        XCTAssertEqual(harness.fakeHUD.limitWarningCount, 1)
        await harness.release()
        await harness.coordinator.waitForDictationCompletion()
    }

    func testNoFocusSnapshotCapturedSavesAsFocusChanged() async {
        let harness = CoordinatorHarness(transcript: "no focus", focusStillMatches: false)
        harness.fakeFocusTracker.focusToReturn = nil
        await harness.pressReleaseAndComplete()
        XCTAssertFalse(harness.inserterWasCalled)
        XCTAssertEqual(harness.savedStatus, .focusChanged)
        XCTAssertEqual(harness.presentedFeedback, .savedToHistory)
    }

    func testAudioStartFailurePresentsErrorFeedback() async {
        let harness = CoordinatorHarness(transcript: "start fail")
        harness.fakeRecorder.shouldFailOnStart = true
        await harness.press()
        await harness.coordinator.waitForDictationCompletion()
        XCTAssertEqual(harness.presentedFeedback, .error("Microphone access denied"))
    }

    func testCoordinatorStopCleansUp() async {
        let harness = CoordinatorHarness(transcript: "cleanup")
        XCTAssertTrue(harness.fakeHotkeyMonitor.isStarted)
        harness.coordinator.stop()
        XCTAssertFalse(harness.fakeHotkeyMonitor.isStarted)
        XCTAssertGreaterThanOrEqual(harness.fakeHUD.hideCallCount, 1)
    }
}
