import XCTest
@testable import SimpleFlow

final class DictationStateMachineTests: XCTestCase {
    // MARK: - Initial State
    func testInitialStateIsIdle() {
        let machine = DictationStateMachine()
        XCTAssertEqual(machine.phase, .idle)
    }

    // MARK: - Idle Transitions
    func testPressFromIdleStartsRecording() {
        var machine = DictationStateMachine()
        XCTAssertEqual(machine.handle(.hotkeyPressed), [.captureFocus, .startAudio])
        XCTAssertEqual(machine.phase, .recording)
    }

    func testIgnoredEventsInIdle() {
        var machine = DictationStateMachine(phase: .idle)
        XCTAssertEqual(machine.handle(.hotkeyReleased), [])
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(machine.handle(.escapePressed), [])
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(machine.handle(.recordingLimitReached), [])
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(machine.handle(.transcriptionInserted), [])
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(machine.handle(.transcriptionSaved), [])
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(machine.handle(.failed("some error")), [])
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(machine.handle(.feedbackExpired), [])
        XCTAssertEqual(machine.phase, .idle)
    }

    // MARK: - Recording Transitions
    func testRepeatedPressWhileRecordingIsIgnored() {
        var machine = DictationStateMachine(phase: .recording)
        XCTAssertEqual(machine.handle(.hotkeyPressed), [])
        XCTAssertEqual(machine.phase, .recording)
    }

    func testReleaseWhileRecordingStopsAndTranscribes() {
        var machine = DictationStateMachine(phase: .recording)
        XCTAssertEqual(machine.handle(.hotkeyReleased), [.stopAndTranscribe])
        XCTAssertEqual(machine.phase, .transcribing)
    }

    func testLimitReachedWhileRecordingUsesNormalSubmissionPath() {
        var machine = DictationStateMachine(phase: .recording)
        XCTAssertEqual(machine.handle(.recordingLimitReached), [.stopAndTranscribe])
        XCTAssertEqual(machine.phase, .transcribing)
    }

    func testEscapeCancelsWhileRecording() {
        var machine = DictationStateMachine(phase: .recording)
        XCTAssertEqual(machine.handle(.escapePressed), [.cancelAudio, .returnToIdle])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testFailureWhileRecordingEntersErrorFeedback() {
        var machine = DictationStateMachine(phase: .recording)
        XCTAssertEqual(machine.handle(.failed("Audio failed")), [])
        XCTAssertEqual(machine.phase, .feedback(.error("Audio failed")))
    }

    func testIgnoredEventsInRecording() {
        var machine = DictationStateMachine(phase: .recording)
        XCTAssertEqual(machine.handle(.transcriptionInserted), [])
        XCTAssertEqual(machine.phase, .recording)

        XCTAssertEqual(machine.handle(.transcriptionSaved), [])
        XCTAssertEqual(machine.phase, .recording)

        XCTAssertEqual(machine.handle(.feedbackExpired), [])
        XCTAssertEqual(machine.phase, .recording)
    }

    // MARK: - Transcribing Transitions
    func testTranscriptionInsertedWhileTranscribingEntersInsertedFeedback() {
        var machine = DictationStateMachine(phase: .transcribing)
        XCTAssertEqual(machine.handle(.transcriptionInserted), [])
        XCTAssertEqual(machine.phase, .feedback(.inserted))
    }

    func testTranscriptionSavedWhileTranscribingEntersSavedFeedback() {
        var machine = DictationStateMachine(phase: .transcribing)
        XCTAssertEqual(machine.handle(.transcriptionSaved), [])
        XCTAssertEqual(machine.phase, .feedback(.savedToHistory))
    }

    func testFailureWhileTranscribingEntersErrorFeedback() {
        var machine = DictationStateMachine(phase: .transcribing)
        XCTAssertEqual(machine.handle(.failed("API error")), [])
        XCTAssertEqual(machine.phase, .feedback(.error("API error")))
    }

    func testIgnoredEventsInTranscribing() {
        var machine = DictationStateMachine(phase: .transcribing)
        XCTAssertEqual(machine.handle(.hotkeyPressed), [])
        XCTAssertEqual(machine.phase, .transcribing)

        XCTAssertEqual(machine.handle(.hotkeyReleased), [])
        XCTAssertEqual(machine.phase, .transcribing)

        XCTAssertEqual(machine.handle(.escapePressed), [])
        XCTAssertEqual(machine.phase, .transcribing)

        XCTAssertEqual(machine.handle(.recordingLimitReached), [])
        XCTAssertEqual(machine.phase, .transcribing)

        XCTAssertEqual(machine.handle(.feedbackExpired), [])
        XCTAssertEqual(machine.phase, .transcribing)
    }

    // MARK: - Feedback Transitions
    func testFeedbackExpiredReturnsToIdle() {
        var machine = DictationStateMachine(phase: .feedback(.inserted))
        XCTAssertEqual(machine.handle(.feedbackExpired), [.returnToIdle])
        XCTAssertEqual(machine.phase, .idle)

        var errorMachine = DictationStateMachine(phase: .feedback(.error("something")))
        XCTAssertEqual(errorMachine.handle(.feedbackExpired), [.returnToIdle])
        XCTAssertEqual(errorMachine.phase, .idle)

        var savedMachine = DictationStateMachine(phase: .feedback(.savedToHistory))
        XCTAssertEqual(savedMachine.handle(.feedbackExpired), [.returnToIdle])
        XCTAssertEqual(savedMachine.phase, .idle)

        var cancelledMachine = DictationStateMachine(phase: .feedback(.cancelled))
        XCTAssertEqual(cancelledMachine.handle(.feedbackExpired), [.returnToIdle])
        XCTAssertEqual(cancelledMachine.phase, .idle)
    }

    func testIgnoredEventsInFeedback() {
        var machine = DictationStateMachine(phase: .feedback(.inserted))
        XCTAssertEqual(machine.handle(.hotkeyPressed), [])
        XCTAssertEqual(machine.phase, .feedback(.inserted))

        XCTAssertEqual(machine.handle(.hotkeyReleased), [])
        XCTAssertEqual(machine.phase, .feedback(.inserted))

        XCTAssertEqual(machine.handle(.escapePressed), [])
        XCTAssertEqual(machine.phase, .feedback(.inserted))

        XCTAssertEqual(machine.handle(.recordingLimitReached), [])
        XCTAssertEqual(machine.phase, .feedback(.inserted))

        XCTAssertEqual(machine.handle(.transcriptionInserted), [])
        XCTAssertEqual(machine.phase, .feedback(.inserted))

        XCTAssertEqual(machine.handle(.transcriptionSaved), [])
        XCTAssertEqual(machine.phase, .feedback(.inserted))

        XCTAssertEqual(machine.handle(.failed("ignore")), [])
        XCTAssertEqual(machine.phase, .feedback(.inserted))
    }

    // MARK: - End-to-End Lifecycle Sequences
    func testCompleteSuccessLifecycle() {
        var machine = DictationStateMachine()
        XCTAssertEqual(machine.phase, .idle)

        // 1. Hotkey pressed
        let pressEffects = machine.handle(.hotkeyPressed)
        XCTAssertEqual(pressEffects, [.captureFocus, .startAudio])
        XCTAssertEqual(machine.phase, .recording)

        // 2. Hotkey released
        let releaseEffects = machine.handle(.hotkeyReleased)
        XCTAssertEqual(releaseEffects, [.stopAndTranscribe])
        XCTAssertEqual(machine.phase, .transcribing)

        // 3. Transcription inserted
        let insertedEffects = machine.handle(.transcriptionInserted)
        XCTAssertEqual(insertedEffects, [])
        XCTAssertEqual(machine.phase, .feedback(.inserted))

        // 4. Feedback expired
        let expiredEffects = machine.handle(.feedbackExpired)
        XCTAssertEqual(expiredEffects, [.returnToIdle])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testCompleteHistoryFallbackLifecycle() {
        var machine = DictationStateMachine()

        // 1. Hotkey pressed
        _ = machine.handle(.hotkeyPressed)
        XCTAssertEqual(machine.phase, .recording)

        // 2. Hotkey released
        _ = machine.handle(.hotkeyReleased)
        XCTAssertEqual(machine.phase, .transcribing)

        // 3. Transcription saved to history (e.g. accessibility insertion failed)
        let savedEffects = machine.handle(.transcriptionSaved)
        XCTAssertEqual(savedEffects, [])
        XCTAssertEqual(machine.phase, .feedback(.savedToHistory))

        // 4. Feedback expired
        let expiredEffects = machine.handle(.feedbackExpired)
        XCTAssertEqual(expiredEffects, [.returnToIdle])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testCompleteErrorLifecycle() {
        var machine = DictationStateMachine()

        // 1. Hotkey pressed
        _ = machine.handle(.hotkeyPressed)
        XCTAssertEqual(machine.phase, .recording)

        // 2. Hotkey released
        _ = machine.handle(.hotkeyReleased)
        XCTAssertEqual(machine.phase, .transcribing)

        // 3. Transcription failed
        let failEffects = machine.handle(.failed("Network timeout"))
        XCTAssertEqual(failEffects, [])
        XCTAssertEqual(machine.phase, .feedback(.error("Network timeout")))

        // 4. Feedback expired
        let expiredEffects = machine.handle(.feedbackExpired)
        XCTAssertEqual(expiredEffects, [.returnToIdle])
        XCTAssertEqual(machine.phase, .idle)
    }
}
