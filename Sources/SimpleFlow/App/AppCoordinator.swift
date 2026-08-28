import ApplicationServices
import Foundation
import Combine

@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var phase: DictationPhase = .idle

    private var stateMachine = DictationStateMachine()
    private let hotkeyMonitor: HotkeyMonitoring
    private let audioRecorder: AudioRecording
    private let focusTracker: FocusTracking
    private let transcriptionClient: Transcribing
    private let textInserter: TextInserting
    private let historyRepository: HistoryStoring
    private let settingsStore: SettingsStore
    private let hudPresenter: HUDPresenting

    private var originalFocus: FocusSnapshot?
    public private(set) var activeStartTask: Task<Void, Never>?
    public private(set) var activeDictationTask: Task<Void, Never>?
    private var feedbackTimerTask: Task<Void, Never>?

    public init(
        hotkeyMonitor: HotkeyMonitoring,
        audioRecorder: AudioRecording,
        focusTracker: FocusTracking,
        transcriptionClient: Transcribing,
        textInserter: TextInserting,
        historyRepository: HistoryStoring,
        settingsStore: SettingsStore,
        hudPresenter: HUDPresenting
    ) {
        self.hotkeyMonitor = hotkeyMonitor
        self.audioRecorder = audioRecorder
        self.focusTracker = focusTracker
        self.transcriptionClient = transcriptionClient
        self.textInserter = textInserter
        self.historyRepository = historyRepository
        self.settingsStore = settingsStore
        self.hudPresenter = hudPresenter
    }

    public func start() {
        audioRecorder.onLimitWarning = { [weak self] in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleLimitWarning()
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.handleLimitWarning()
                }
            }
        }

        audioRecorder.onLimitReached = { [weak self] in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleLimitReached()
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.handleLimitReached()
                }
            }
        }

        do {
            try hotkeyMonitor.start(
                hotkey: settingsStore.hotkey,
                onPress: { [weak self] in
                    self?.handleHotkeyPressed()
                },
                onRelease: { [weak self] in
                    self?.handleHotkeyReleased()
                },
                onCancel: { [weak self] in
                    self?.handleEscapePressed()
                }
            )
        } catch {
            handleFailure(error)
        }
    }

    public func stop() {
        hotkeyMonitor.stop()
        audioRecorder.onLimitWarning = nil
        audioRecorder.onLimitReached = nil

        feedbackTimerTask?.cancel()
        feedbackTimerTask = nil

        activeDictationTask?.cancel()
        activeDictationTask = nil

        activeStartTask?.cancel()
        activeStartTask = nil

        hudPresenter.hide()
        stateMachine = DictationStateMachine(phase: .idle)
        phase = .idle
        originalFocus = nil
    }

    public func handleHotkeyPressed() {
        feedbackTimerTask?.cancel()
        feedbackTimerTask = nil

        let effects = stateMachine.handle(.hotkeyPressed)
        guard !effects.isEmpty else { return }

        phase = stateMachine.phase
        hudPresenter.show(phase)

        if effects.contains(.captureFocus) {
            originalFocus = focusTracker.capture()
        }

        if effects.contains(.startAudio) {
            let deviceUID = settingsStore.microphoneDeviceUID
            activeStartTask = Task { @MainActor [weak self, audioRecorder] in
                guard let self = self else { return }
                do {
                    try await audioRecorder.start(deviceUID: deviceUID)
                } catch {
                    self.handleFailure(error)
                }
            }
        }
    }

    public func handleHotkeyReleased() {
        let effects = stateMachine.handle(.hotkeyReleased)
        guard !effects.isEmpty else { return }

        phase = stateMachine.phase
        hudPresenter.show(phase)

        if effects.contains(.stopAndTranscribe) {
            activeDictationTask = Task { @MainActor [weak self] in
                await self?.performTranscriptionAndInsertion()
            }
        }
    }

    public func handleLimitReached() {
        let effects = stateMachine.handle(.recordingLimitReached)
        guard !effects.isEmpty else { return }

        phase = stateMachine.phase
        hudPresenter.show(phase)

        if effects.contains(.stopAndTranscribe) {
            activeDictationTask = Task { @MainActor [weak self] in
                await self?.performTranscriptionAndInsertion()
            }
        }
    }

    public func handleLimitWarning() {
        guard phase == .recording else { return }
        hudPresenter.showLimitWarning()
    }

    public func handleEscapePressed() {
        let effects = stateMachine.handle(.escapePressed)
        guard !effects.isEmpty else { return }

        originalFocus = nil
        activeStartTask?.cancel()
        activeStartTask = nil

        phase = stateMachine.phase
        hudPresenter.hide()

        if effects.contains(.cancelAudio) {
            activeDictationTask = Task { [audioRecorder] in
                await audioRecorder.cancel()
            }
        }
    }

    public func waitForDictationCompletion() async {
        await activeStartTask?.value
        await activeDictationTask?.value
    }

    private func performTranscriptionAndInsertion() async {
        await activeStartTask?.value

        let audio: RecordedAudio
        do {
            audio = try await audioRecorder.stop()
        } catch {
            handleFailure(error)
            return
        }

        do {
            try await processTranscriptionAndInsert(audio: audio)
        } catch {
            handleFailure(error)
        }

        await audioRecorder.remove(audio)
    }

    private func processTranscriptionAndInsert(audio: RecordedAudio) async throws {
        let config = try settingsStore.transcriptionConfiguration()
        let text = try await transcriptionClient.transcribe(fileURL: audio.fileURL, configuration: config)

        let matches: Bool
        if let originalFocus = originalFocus {
            matches = focusTracker.stillMatches(originalFocus)
        } else {
            matches = false
        }

        let record = try historyRepository.save(
            text: text,
            sourceApplicationName: originalFocus?.applicationName,
            insertionStatus: matches ? .pasteFailed : .focusChanged
        )

        guard matches else {
            _ = stateMachine.handle(.transcriptionSaved)
            phase = stateMachine.phase
            hudPresenter.show(phase)
            scheduleFeedbackExpiry(delay: 1.5)
            return
        }

        let insertResult = await textInserter.insert(text)
        if insertResult == .inserted {
            try? historyRepository.updateInsertionStatus(record, to: .inserted)
            _ = stateMachine.handle(.transcriptionInserted)
            phase = stateMachine.phase
            hudPresenter.show(phase)
            scheduleFeedbackExpiry(delay: 1.5)
        } else {
            _ = stateMachine.handle(.transcriptionSaved)
            phase = stateMachine.phase
            hudPresenter.show(phase)
            scheduleFeedbackExpiry(delay: 1.5)
        }
    }

    private func handleFailure(_ error: Error) {
        let message = sanitizeErrorMessage(error)
        _ = stateMachine.handle(.failed(message))
        phase = stateMachine.phase
        hudPresenter.show(phase)
        scheduleFeedbackExpiry(delay: 4.0)
    }

    private func sanitizeErrorMessage(_ error: Error) -> String {
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .transport(let code):
                if code == .notConnectedToInternet {
                    return "No internet connection"
                } else if code == .timedOut {
                    return "Request timed out"
                } else if code == .networkConnectionLost {
                    return "Network connection lost"
                } else if code == .cannotConnectToHost || code == .cannotFindHost {
                    return "Cannot connect to server"
                } else {
                    return "Network error"
                }
            case .unauthorized:
                return "Unauthorized. Please check your API token."
            case .noSpeech:
                return "No speech detected"
            case .server(let status):
                return "Server error (\(status))"
            case .fileUnavailable:
                return "Audio file unavailable"
            case .invalidConfiguration:
                return "Invalid configuration"
            case .malformedResponse:
                return "Malformed server response"
            }
        }

        if let configError = error as? TranscriptionConfigurationError {
            switch configError {
            case .missingToken:
                return "API token not configured"
            case .missingModel:
                return "Model not configured"
            case .invalidBaseURL:
                return "Invalid API URL"
            case .invalidEndpoint:
                return "Invalid API endpoint"
            }
        }

        if let audioError = error as? AudioRecorderError {
            switch audioError {
            case .permissionDenied:
                return "Microphone access denied"
            case .noDeviceAvailable:
                return "No microphone available"
            case .deviceNotFound:
                return "Microphone device not found"
            default:
                return "Audio recording error"
            }
        }

        if let hotkeyError = error as? HotkeyMonitorError {
            switch hotkeyError {
            case .accessibilityPermissionRequired:
                return "Accessibility permission required"
            case .tapCreationFailed:
                return "Failed to monitor hotkey"
            }
        }

        if let historyError = error as? HistoryError {
            switch historyError {
            case .emptyText:
                return "No text to save"
            }
        }

        return error.localizedDescription
    }

    private func scheduleFeedbackExpiry(delay: TimeInterval) {
        feedbackTimerTask?.cancel()
        feedbackTimerTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self = self, !Task.isCancelled else { return }
            _ = self.stateMachine.handle(.feedbackExpired)
            self.phase = self.stateMachine.phase
            self.hudPresenter.hide()
        }
    }
}
