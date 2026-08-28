import AppKit
import SwiftData
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public static private(set) var shared: AppDelegate?

    public private(set) var coordinator: AppCoordinator?
    public private(set) var modelContainer: ModelContainer?
    public private(set) var settingsStore: SettingsStore?

    private var settingsWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?

    public override init() {
        super.init()
        AppDelegate.shared = self
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
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

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showSettingsWindow()
        }
        return true
    }

    @MainActor
    public func showSettingsWindow() {
        if let controller = settingsWindowController, let window = controller.window {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let coordinator = coordinator, let settingsStore = settingsStore else { return }
        AppLogger.lifecycle.info("Opening Settings window")

        let viewModel = SettingsViewModel(settingsStore: settingsStore, coordinator: coordinator)
        let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Simple Flow Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let controller = NSWindowController(window: window)
        self.settingsWindowController = controller

        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    public func showHistoryWindow() {
        if let controller = historyWindowController, let window = controller.window {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let container = modelContainer else { return }
        AppLogger.lifecycle.info("Opening History window")

        let historyView = HistoryView().modelContainer(container)
        let hostingController = NSHostingController(rootView: historyView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Simple Flow History"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let controller = NSWindowController(window: window)
        self.historyWindowController = controller

        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    public func showOnboardingWindow() {
        if let controller = onboardingWindowController, let window = controller.window {
            NSApp.setActivationPolicy(.regular)
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
            self?.coordinator?.restartHotkeyMonitor()
            self?.updateActivationPolicy()
        }

        let hostingController = NSHostingController(rootView: OnboardingView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Simple Flow"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let controller = NSWindowController(window: window)
        self.onboardingWindowController = controller

        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.updateActivationPolicy()
        }
    }

    @MainActor
    private func updateActivationPolicy() {
        let hasVisibleWindows = [
            settingsWindowController?.window?.isVisible == true,
            historyWindowController?.window?.isVisible == true,
            onboardingWindowController?.window?.isVisible == true
        ].contains(true)

        if hasVisibleWindows {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
