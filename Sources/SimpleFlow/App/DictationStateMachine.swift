import Foundation

public enum FeedbackKind: Equatable, Sendable {
    case inserted
    case savedToHistory
    case cancelled
    case error(String)
}

public enum DictationPhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case feedback(FeedbackKind)
}

public enum DictationEvent: Equatable, Sendable {
    case hotkeyPressed
    case hotkeyReleased
    case escapePressed
    case recordingLimitReached
    case transcriptionInserted
    case transcriptionSaved
    case failed(String)
    case feedbackExpired
}

public enum DictationEffect: Equatable, Sendable {
    case captureFocus
    case startAudio
    case stopAndTranscribe
    case cancelAudio
    case returnToIdle
}

public struct DictationStateMachine: Sendable {
    public private(set) var phase: DictationPhase

    public init(phase: DictationPhase = .idle) {
        self.phase = phase
    }

    public mutating func handle(_ event: DictationEvent) -> [DictationEffect] {
        switch (phase, event) {
        case (.idle, .hotkeyPressed), (.feedback, .hotkeyPressed):
            phase = .recording
            return [.captureFocus, .startAudio]

        case (.recording, .hotkeyReleased), (.recording, .recordingLimitReached):
            phase = .transcribing
            return [.stopAndTranscribe]

        case (.recording, .escapePressed), (.feedback, .escapePressed):
            phase = .idle
            return [.cancelAudio, .returnToIdle]

        case (.recording, .failed(let message)), (.transcribing, .failed(let message)):
            phase = .feedback(.error(message))
            return []

        case (.transcribing, .transcriptionInserted):
            phase = .feedback(.inserted)
            return []

        case (.transcribing, .transcriptionSaved):
            phase = .feedback(.savedToHistory)
            return []

        case (.feedback, .feedbackExpired):
            phase = .idle
            return [.returnToIdle]

        default:
            return []
        }
    }
}
