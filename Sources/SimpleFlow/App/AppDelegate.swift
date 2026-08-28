import AppKit
import SwiftData
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var coordinator: AppCoordinator?
    public private(set) var modelContainer: ModelContainer?
    public private(set) var settingsStore: SettingsStore?
    private var onboardingWindowController: NSWindowController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.lifecycle.info("Simple Flow launched (bundleID: \(AppIdentity.bundleIdentifier, privacy: .public))")
        NSApp.setActivationPolicy(.accessory)

        do {
            let container = try ModelContainer(for: TranscriptRecord.self)
            self.modelContainer = container

            let settingsStore = SettingsStore()
            self.settingsStore = settingsStore

            AudioRecorder.cleanupAbandonedRecordings()

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

            if !settingsStore.hasCompletedOnboarding {
                showOnboardingWindow()
            }
        } catch {
            AppLogger.lifecycle.error("Failed to initialize SimpleFlow dependencies: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        AppLogger.lifecycle.info("Simple Flow terminating")
        coordinator?.stop()
    }

    @MainActor
    public func showOnboardingWindow() {
        if let controller = onboardingWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let settingsStore = settingsStore else { return }
        AppLogger.lifecycle.info("Presenting first-launch onboarding window")

        let viewModel = OnboardingViewModel(settingsStore: settingsStore)
        viewModel.onFinish = { [weak self] in
            self?.onboardingWindowController?.close()
            self?.onboardingWindowController = nil
        }

        let hostingController = NSHostingController(rootView: OnboardingView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Simple Flow"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        self.onboardingWindowController = controller

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
