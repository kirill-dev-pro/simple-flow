import SwiftData
import SwiftUI

@main
struct SimpleFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Simple Flow", systemImage: menuBarIcon) {
            MenuBarContent(coordinator: appDelegate.coordinator)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(for: TranscriptRecord.self)

        Window("History", id: "history") {
            HistoryView()
        }
        .modelContainer(for: TranscriptRecord.self)

        Window("Settings", id: "settings") {
            if let coordinator = appDelegate.coordinator, let settingsStore = appDelegate.settingsStore {
                SettingsView(viewModel: SettingsViewModel(settingsStore: settingsStore, coordinator: coordinator))
            } else {
                SettingsView(viewModel: SettingsViewModel())
            }
        }
        .modelContainer(for: TranscriptRecord.self)

        Window("Welcome to Simple Flow", id: "onboarding") {
            if let settingsStore = appDelegate.settingsStore {
                OnboardingView(viewModel: OnboardingViewModel(settingsStore: settingsStore))
            } else {
                OnboardingView(viewModel: OnboardingViewModel())
            }
        }
        .modelContainer(for: TranscriptRecord.self)
    }

    private var menuBarIcon: String {
        guard let phase = appDelegate.coordinator?.phase else {
            return "mic"
        }
        switch phase {
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
}
