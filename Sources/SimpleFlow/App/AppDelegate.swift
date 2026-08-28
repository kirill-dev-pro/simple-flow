import AppKit
import SwiftData

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var coordinator: AppCoordinator?
    public private(set) var modelContainer: ModelContainer?
    public private(set) var settingsStore: SettingsStore?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let container = try ModelContainer(for: TranscriptRecord.self)
            self.modelContainer = container

            let settingsStore = SettingsStore()
            self.settingsStore = settingsStore

            let coordinator = AppCoordinator(
                hotkeyMonitor: HotkeyMonitor(),
                audioRecorder: AudioRecorder(),
                focusTracker: SystemFocusTracker(),
                transcriptionClient: TranscriptionClient(),
                textInserter: TextInserter(),
                historyRepository: HistoryRepository(context: container.mainContext),
                settingsStore: settingsStore,
                hudPresenter: FloatingHUDController()
            )
            self.coordinator = coordinator
            coordinator.start()
        } catch {
            NSLog("Failed to initialize SimpleFlow dependencies: %@", error.localizedDescription)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
