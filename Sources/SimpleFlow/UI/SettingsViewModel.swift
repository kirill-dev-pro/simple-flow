import Combine
import CoreGraphics
import Foundation

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var baseURL: String
    @Published public var token: String
    @Published public var model: String
    @Published public var isTokenRevealed: Bool = false
    @Published public var microphoneDeviceUID: String?
    @Published public var hotkey: Hotkey
    @Published public var launchAtLogin: Bool
    @Published public var errorMessage: String?
    @Published public var testConnectionResult: ConnectionTestResult?
    @Published public var isTestingConnection: Bool = false
    @Published public var microphoneStatus: PermissionStatus = .notDetermined
    @Published public var accessibilityStatus: PermissionStatus = .notDetermined
    @Published public var availableMicrophones: [AudioInputDevice] = []

    public let settingsStore: SettingsStore
    public let permissionManager: PermissionManaging
    public let microphoneCatalog: MicrophoneCataloging
    public let launchAtLoginController: LaunchAtLoginControlling
    public let transcriptionClient: Transcribing
    public var onRestartHotkeyMonitor: (@MainActor () -> Void)?
    public var onSaveHotkey: (@MainActor () -> Void)?

    public init(
        settingsStore: SettingsStore = SettingsStore(),
        permissionManager: PermissionManaging = PermissionManager(),
        microphoneCatalog: MicrophoneCataloging = MicrophoneCatalog(),
        launchAtLoginController: LaunchAtLoginControlling = LaunchAtLoginController(),
        transcriptionClient: Transcribing = TranscriptionClient(),
        onRestartHotkeyMonitor: (@MainActor () -> Void)? = nil,
        onSaveHotkey: (@MainActor () -> Void)? = nil
    ) {
        self.settingsStore = settingsStore
        self.permissionManager = permissionManager
        self.microphoneCatalog = microphoneCatalog
        self.launchAtLoginController = launchAtLoginController
        self.transcriptionClient = transcriptionClient
        self.onRestartHotkeyMonitor = onRestartHotkeyMonitor
        self.onSaveHotkey = onSaveHotkey

        self.baseURL = settingsStore.baseURL
        self.token = (try? settingsStore.readToken()) ?? ""
        self.model = settingsStore.model
        self.microphoneDeviceUID = settingsStore.microphoneDeviceUID
        self.hotkey = settingsStore.hotkey
        self.launchAtLogin = launchAtLoginController.isEnabled

        refreshPermissions()
        refreshMicrophones()
    }

    public convenience init(settingsStore: SettingsStore, coordinator: AppCoordinator) {
        self.init(
            settingsStore: settingsStore,
            onRestartHotkeyMonitor: { [weak coordinator] in
                coordinator?.restartHotkeyMonitor()
            }
        )
    }

    public func refreshPermissions() {
        self.microphoneStatus = permissionManager.microphoneStatus
        self.accessibilityStatus = permissionManager.accessibilityStatus
    }

    public func refreshMicrophones() {
        self.availableMicrophones = microphoneCatalog.availableDevices()
    }

    public func requestMicrophonePermission() async {
        _ = await permissionManager.requestMicrophoneAccess()
        refreshPermissions()
    }

    public func requestAccessibilityPermission() {
        _ = permissionManager.requestAccessibilityAccess()
        refreshPermissions()
    }

    public func openMicrophoneSettings() {
        permissionManager.openMicrophoneSettings()
    }

    public func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    public func setLaunchAtLogin(_ enabled: Bool) async {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLogin = enabled
            settingsStore.launchAtLogin = enabled
            errorMessage = nil
        } catch {
            launchAtLogin = false
            errorMessage = "Could not enable Launch at Login"
        }
    }

    public func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }

        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = TranscriptionConfiguration(baseURL: trimmedBaseURL, token: trimmedToken, model: trimmedModel)
        let result = await transcriptionClient.testConnection(configuration: config)
        testConnectionResult = result
    }

    public func apply() async {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedBaseURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let host = url.host,
              !host.isEmpty else {
            errorMessage = "Enter a valid HTTPS URL"
            return
        }

        let oldHotkey = settingsStore.hotkey
        let hotkeyChanged = (oldHotkey != hotkey)

        settingsStore.baseURL = trimmedBaseURL
        settingsStore.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.microphoneDeviceUID = microphoneDeviceUID

        if !token.isEmpty {
            try? settingsStore.saveToken(token)
        } else {
            try? settingsStore.deleteToken()
        }

        settingsStore.hotkey = hotkey
        onSaveHotkey?()

        if hotkeyChanged || onRestartHotkeyMonitor != nil {
            onRestartHotkeyMonitor?()
        }

        errorMessage = nil
    }
}
