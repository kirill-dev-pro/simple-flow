import Combine
import Foundation

@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public var microphoneStatus: PermissionStatus
    @Published public var accessibilityStatus: PermissionStatus

    public let permissionManager: PermissionManaging
    public let settingsStore: SettingsStore

    public var canFinish: Bool {
        microphoneStatus == .granted && accessibilityStatus == .granted
    }

    public init(
        microphone: PermissionStatus,
        accessibility: PermissionStatus,
        settingsStore: SettingsStore = SettingsStore(),
        permissionManager: PermissionManaging = PermissionManager()
    ) {
        self.microphoneStatus = microphone
        self.accessibilityStatus = accessibility
        self.settingsStore = settingsStore
        self.permissionManager = permissionManager
    }

    public init(
        permissionManager: PermissionManaging = PermissionManager(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        self.permissionManager = permissionManager
        self.settingsStore = settingsStore
        self.microphoneStatus = permissionManager.microphoneStatus
        self.accessibilityStatus = permissionManager.accessibilityStatus
    }

    public func refreshPermissions() {
        self.microphoneStatus = permissionManager.microphoneStatus
        self.accessibilityStatus = permissionManager.accessibilityStatus
    }

    public func requestMicrophoneAccess() async {
        _ = await permissionManager.requestMicrophoneAccess()
        refreshPermissions()
    }

    public func requestAccessibilityAccess() {
        _ = permissionManager.requestAccessibilityAccess()
        refreshPermissions()
    }

    public func openMicrophoneSettings() {
        permissionManager.openMicrophoneSettings()
    }

    public func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    public var onFinish: (@MainActor () -> Void)?

    public func finish() {
        guard canFinish else { return }
        settingsStore.hasCompletedOnboarding = true
        onFinish?()
    }
}
