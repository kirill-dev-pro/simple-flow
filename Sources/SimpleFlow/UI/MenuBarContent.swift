import AppKit
import Carbon
import SwiftData
import SwiftUI

public struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TranscriptRecord.createdAt, order: .reverse) private var records: [TranscriptRecord]
    @ObservedObject private var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator? = nil) {
        if let coordinator = coordinator {
            self.coordinator = coordinator
        } else {
            // Fallback for previews
            self.coordinator = AppCoordinator(
                hotkeyMonitor: HotkeyMonitor(),
                audioRecorder: AudioRecorder(),
                focusTracker: SystemFocusTracker(),
                transcriptionClient: TranscriptionClient(),
                textInserter: TextInserter(),
                historyRepository: HistoryRepository(context: try! ModelContainer(for: TranscriptRecord.self).mainContext),
                settingsStore: SettingsStore(),
                hudPresenter: FloatingHUDController()
            )
        }
    }

    public var body: some View {
        statusSection

        if HotkeyMonitorDiagnostic.secureInputEnabled {
            Text("⚠️ Secure Keyboard Entry is active (may block push-to-talk)")
            Divider()
        }

        Button("History…") {
            openWindow(id: "history")
        }

        Button("Copy Last Transcript") {
            copyLastTranscript()
        }
        .disabled(records.isEmpty)

        Button("Settings…") {
            openWindow(id: "settings")
        }

        Divider()

        Button("Quit Simple Flow") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var statusSection: some View {
        HStack {
            Image(systemName: phaseIcon)
            Text(statusTitle)
        }
        Divider()
    }

    private var statusTitle: String {
        switch coordinator.phase {
        case .idle:
            return "Status: Ready"
        case .recording:
            return "Status: Recording…"
        case .transcribing:
            return "Status: Transcribing…"
        case .feedback(let kind):
            switch kind {
            case .inserted:
                return "Inserted"
            case .savedToHistory:
                return "Saved to History"
            case .cancelled:
                return "Cancelled"
            case .error(let message):
                return "Error: \(message)"
            }
        }
    }

    private var phaseIcon: String {
        switch coordinator.phase {
        case .idle:
            return "mic"
        case .recording:
            return "record.circle"
        case .transcribing:
            return "waveform"
        case .feedback(let kind):
            switch kind {
            case .inserted:
                return "checkmark.circle"
            case .savedToHistory:
                return "doc.on.clipboard"
            case .cancelled:
                return "xmark.circle"
            case .error:
                return "exclamationmark.triangle"
            }
        }
    }

    private func copyLastTranscript() {
        guard let latest = records.first?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latest, forType: .string)
    }
}
