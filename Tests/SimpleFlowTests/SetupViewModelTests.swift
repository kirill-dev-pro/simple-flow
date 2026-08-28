import CoreGraphics
import XCTest
@testable import SimpleFlow

enum SetupCall: Equatable {
    case saveBaseURL
    case saveModel
    case saveMicrophone
    case saveHotkey
    case saveToken
    case restartHotkeyMonitor
    case setLaunchAtLogin(Bool)
}

enum TestError: Error, Equatable {
    case registrationDenied
    case testFailure
}

final class FakePermissionManager: PermissionManaging, @unchecked Sendable {
    var microphoneStatus: PermissionStatus
    var accessibilityStatus: PermissionStatus
    var requestMicrophoneResult: Bool
    var requestAccessibilityResult: Bool
    var openedMicrophoneSettings = false
    var openedAccessibilitySettings = false

    init(
        microphoneStatus: PermissionStatus = .notDetermined,
        accessibilityStatus: PermissionStatus = .notDetermined,
        requestMicrophoneResult: Bool = true,
        requestAccessibilityResult: Bool = true
    ) {
        self.microphoneStatus = microphoneStatus
        self.accessibilityStatus = accessibilityStatus
        self.requestMicrophoneResult = requestMicrophoneResult
        self.requestAccessibilityResult = requestAccessibilityResult
    }

    func requestMicrophoneAccess() async -> Bool {
        if requestMicrophoneResult {
            microphoneStatus = .granted
        } else {
            microphoneStatus = .denied
        }
        return requestMicrophoneResult
    }

    func requestAccessibilityAccess() -> Bool {
        if requestAccessibilityResult {
            accessibilityStatus = .granted
        } else {
            accessibilityStatus = .denied
        }
        return requestAccessibilityResult
    }

    func openMicrophoneSettings() {
        openedMicrophoneSettings = true
    }

    func openAccessibilitySettings() {
        openedAccessibilitySettings = true
    }
}

final class FakeMicrophoneCatalog: MicrophoneCataloging, @unchecked Sendable {
    var devices: [AudioInputDevice]

    init(devices: [AudioInputDevice] = [.systemDefault, AudioInputDevice(uid: "mic-1", name: "External Mic")]) {
        self.devices = devices
    }

    func availableDevices() -> [AudioInputDevice] {
        devices
    }
}

final class FakeLaunchAtLoginController: LaunchAtLoginControlling, @unchecked Sendable {
    var isEnabled: Bool
    var result: Result<Void, Error>
    var onSetEnabled: ((Bool) -> Void)?

    init(isEnabled: Bool = false, result: Result<Void, Error> = .success(())) {
        self.isEnabled = isEnabled
        self.result = result
    }

    func setEnabled(_ enabled: Bool) throws {
        onSetEnabled?(enabled)
        try result.get()
        self.isEnabled = enabled
    }
}

final class FakeTranscriptionClient: Transcribing, @unchecked Sendable {
    var connectionResult: ConnectionTestResult = .reachable
    var transcribeResult: Result<String, Error> = .success("Transcribed text")

    func transcribe(fileURL: URL, configuration: TranscriptionConfiguration) async throws -> String {
        try transcribeResult.get()
    }

    func testConnection(configuration: TranscriptionConfiguration) async -> ConnectionTestResult {
        connectionResult
    }
}

@MainActor
final class SetupHarness {
    var calls: [SetupCall] = []
    let userDefaults: UserDefaults
    let suiteName: String
    let tokenStore: InMemoryTokenStore
    let settingsStore: SettingsStore
    let permissionManager: FakePermissionManager
    let microphoneCatalog: FakeMicrophoneCatalog
    let launchAtLoginController: FakeLaunchAtLoginController
    let transcriptionClient: FakeTranscriptionClient
    let settingsViewModel: SettingsViewModel

    var persistedBaseURL: String {
        settingsStore.baseURL
    }

    init(
        existingBaseURL: String = "https://working.example/v1",
        existingModel: String = "gigaam",
        existingToken: String? = "test-token",
        existingMicrophoneUID: String? = nil,
        existingHotkey: Hotkey = .functionKey,
        launchAtLoginResult: Result<Void, Error> = .success(()),
        permissionManager: FakePermissionManager = FakePermissionManager(),
        microphoneCatalog: FakeMicrophoneCatalog = FakeMicrophoneCatalog(),
        transcriptionClient: FakeTranscriptionClient = FakeTranscriptionClient()
    ) {
        self.suiteName = "dev.kirill.simpleflow.test.setup.\(UUID().uuidString)"
        self.userDefaults = UserDefaults(suiteName: suiteName)!
        self.tokenStore = InMemoryTokenStore(initialToken: existingToken)
        self.settingsStore = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)

        settingsStore.baseURL = existingBaseURL
        settingsStore.model = existingModel
        settingsStore.microphoneDeviceUID = existingMicrophoneUID
        settingsStore.hotkey = existingHotkey

        self.permissionManager = permissionManager
        self.microphoneCatalog = microphoneCatalog
        self.launchAtLoginController = FakeLaunchAtLoginController(result: launchAtLoginResult)
        self.transcriptionClient = transcriptionClient

        let settingsVM = SettingsViewModel(
            settingsStore: settingsStore,
            permissionManager: permissionManager,
            microphoneCatalog: microphoneCatalog,
            launchAtLoginController: launchAtLoginController,
            transcriptionClient: transcriptionClient
        )
        self.settingsViewModel = settingsVM

        settingsVM.onRestartHotkeyMonitor = { [weak self] in
            self?.calls.append(.restartHotkeyMonitor)
        }
        settingsVM.onSaveHotkey = { [weak self] in
            self?.calls.append(.saveHotkey)
        }

        launchAtLoginController.onSetEnabled = { [weak self] enabled in
            self?.calls.append(.setLaunchAtLogin(enabled))
        }
    }

    deinit {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

final class SetupViewModelTests: XCTestCase {
    @MainActor
    func testApplyRejectsInvalidURLWithoutOverwritingStoredSettings() async {
        let harness = SetupHarness(existingBaseURL: "https://working.example/v1")
        harness.settingsViewModel.baseURL = "not a URL"
        await harness.settingsViewModel.apply()
        XCTAssertEqual(harness.persistedBaseURL, "https://working.example/v1")
        XCTAssertEqual(harness.settingsViewModel.errorMessage, "Enter a valid HTTPS URL")
    }

    @MainActor
    func testChangingHotkeyRestartsMonitorAfterPersistence() async {
        let harness = SetupHarness()
        harness.settingsViewModel.hotkey = Hotkey(keyCode: 49, modifiersRawValue: 0, isFunctionKeyOnly: false)
        await harness.settingsViewModel.apply()
        XCTAssertEqual(Array(harness.calls.suffix(2)), [.saveHotkey, .restartHotkeyMonitor])
    }

    @MainActor
    func testOnboardingRequiresBothPermissions() {
        let microphoneOnly = OnboardingViewModel(microphone: .granted, accessibility: .denied)
        XCTAssertFalse(microphoneOnly.canFinish)
        let complete = OnboardingViewModel(microphone: .granted, accessibility: .granted)
        XCTAssertTrue(complete.canFinish)
    }

    @MainActor
    func testLaunchAtLoginFailureReturnsToggleToOff() async {
        let harness = SetupHarness(launchAtLoginResult: .failure(TestError.registrationDenied))
        await harness.settingsViewModel.setLaunchAtLogin(true)
        XCTAssertFalse(harness.settingsViewModel.launchAtLogin)
        XCTAssertEqual(harness.settingsViewModel.errorMessage, "Could not enable Launch at Login")
    }

    @MainActor
    func testApplyValidSettingsPersistsAllFieldsAndClearsErrorMessage() async {
        let harness = SetupHarness()
        harness.settingsViewModel.baseURL = "https://new.api.example/v1"
        harness.settingsViewModel.token = "new-secret-token"
        harness.settingsViewModel.model = "whisper-large-v3"
        harness.settingsViewModel.microphoneDeviceUID = "mic-1"
        harness.settingsViewModel.errorMessage = "Previous error"

        await harness.settingsViewModel.apply()

        XCTAssertEqual(harness.settingsStore.baseURL, "https://new.api.example/v1")
        XCTAssertEqual(try harness.settingsStore.readToken(), "new-secret-token")
        XCTAssertEqual(harness.settingsStore.model, "whisper-large-v3")
        XCTAssertEqual(harness.settingsStore.microphoneDeviceUID, "mic-1")
        XCTAssertNil(harness.settingsViewModel.errorMessage)
    }

    @MainActor
    func testApplyWithEmptyTokenDeletesToken() async {
        let harness = SetupHarness(existingToken: "existing-token")
        harness.settingsViewModel.token = ""
        await harness.settingsViewModel.apply()

        XCTAssertNil(try harness.settingsStore.readToken())
        XCTAssertNil(harness.settingsViewModel.errorMessage)
    }

    @MainActor
    func testTestConnectionSuccessUpdatesState() async {
        let harness = SetupHarness()
        harness.transcriptionClient.connectionResult = .reachable
        await harness.settingsViewModel.testConnection()
        XCTAssertEqual(harness.settingsViewModel.testConnectionResult, .reachable)
        XCTAssertNil(harness.settingsViewModel.errorMessage)
    }

    @MainActor
    func testTestConnectionUnauthorizedUpdatesState() async {
        let harness = SetupHarness()
        harness.transcriptionClient.connectionResult = .unauthorized
        await harness.settingsViewModel.testConnection()
        XCTAssertEqual(harness.settingsViewModel.testConnectionResult, .unauthorized)
    }

    @MainActor
    func testLaunchAtLoginSuccessEnablesToggle() async {
        let harness = SetupHarness(launchAtLoginResult: .success(()))
        await harness.settingsViewModel.setLaunchAtLogin(true)
        XCTAssertTrue(harness.settingsViewModel.launchAtLogin)
        XCTAssertEqual(harness.calls, [.setLaunchAtLogin(true)])
        XCTAssertNil(harness.settingsViewModel.errorMessage)
    }

    @MainActor
    func testOnboardingFinishPersistsCompletion() {
        let fakePM = FakePermissionManager(microphoneStatus: .granted, accessibilityStatus: .granted)
        let userDefaults = UserDefaults(suiteName: "dev.kirill.simpleflow.test.onboarding.\(UUID().uuidString)")!
        let tokenStore = InMemoryTokenStore()
        let store = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)
        XCTAssertFalse(store.hasCompletedOnboarding)

        let vm = OnboardingViewModel(permissionManager: fakePM, settingsStore: store)
        XCTAssertTrue(vm.canFinish)
        vm.finish()
        XCTAssertTrue(store.hasCompletedOnboarding)
    }

    @MainActor
    func testOnboardingCannotFinishWhenPermissionsIncomplete() {
        let fakePM = FakePermissionManager(microphoneStatus: .notDetermined, accessibilityStatus: .granted)
        let userDefaults = UserDefaults(suiteName: "dev.kirill.simpleflow.test.onboarding.\(UUID().uuidString)")!
        let tokenStore = InMemoryTokenStore()
        let store = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)

        let vm = OnboardingViewModel(permissionManager: fakePM, settingsStore: store)
        XCTAssertFalse(vm.canFinish)
        vm.finish()
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    @MainActor
    func testOnboardingRequestMicrophoneUpdatesStatus() async {
        let fakePM = FakePermissionManager(microphoneStatus: .notDetermined, requestMicrophoneResult: true)
        let vm = OnboardingViewModel(permissionManager: fakePM)
        XCTAssertEqual(vm.microphoneStatus, .notDetermined)

        await vm.requestMicrophoneAccess()
        XCTAssertEqual(vm.microphoneStatus, .granted)
    }

    @MainActor
    func testOnboardingRequestAccessibilityUpdatesStatus() {
        let fakePM = FakePermissionManager(accessibilityStatus: .notDetermined, requestAccessibilityResult: true)
        let vm = OnboardingViewModel(permissionManager: fakePM)
        XCTAssertEqual(vm.accessibilityStatus, .notDetermined)

        vm.requestAccessibilityAccess()
        XCTAssertEqual(vm.accessibilityStatus, .granted)
    }

    @MainActor
    func testOnboardingOpenSettingsCallsPermissionManager() {
        let fakePM = FakePermissionManager()
        let vm = OnboardingViewModel(permissionManager: fakePM)

        vm.openMicrophoneSettings()
        XCTAssertTrue(fakePM.openedMicrophoneSettings)

        vm.openAccessibilitySettings()
        XCTAssertTrue(fakePM.openedAccessibilitySettings)
    }

    @MainActor
    func testSettingsViewModelPermissionAndMicrophoneActions() async {
        let harness = SetupHarness()
        harness.permissionManager.microphoneStatus = .notDetermined
        harness.permissionManager.accessibilityStatus = .notDetermined

        harness.settingsViewModel.refreshPermissions()
        XCTAssertEqual(harness.settingsViewModel.microphoneStatus, .notDetermined)
        XCTAssertEqual(harness.settingsViewModel.accessibilityStatus, .notDetermined)

        await harness.settingsViewModel.requestMicrophonePermission()
        XCTAssertEqual(harness.settingsViewModel.microphoneStatus, .granted)

        harness.settingsViewModel.requestAccessibilityPermission()
        XCTAssertEqual(harness.settingsViewModel.accessibilityStatus, .granted)

        harness.settingsViewModel.openMicrophoneSettings()
        XCTAssertTrue(harness.permissionManager.openedMicrophoneSettings)

        harness.settingsViewModel.openAccessibilitySettings()
        XCTAssertTrue(harness.permissionManager.openedAccessibilitySettings)
    }

    func testHotkeyDisplayString() {
        let fn = Hotkey.functionKey
        XCTAssertEqual(fn.displayString, "fn (Globe)")

        let cmdSpace = Hotkey(keyCode: 49, modifiersRawValue: CGEventFlags.maskCommand.rawValue, isFunctionKeyOnly: false)
        XCTAssertEqual(cmdSpace.displayString, "⌘ Space")

        let complex = Hotkey(
            keyCode: 36,
            modifiersRawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue,
            isFunctionKeyOnly: false
        )
        XCTAssertEqual(complex.displayString, "⌃ ⌥ ⇧ ⌘ Return")
    }

    func testAudioInputDeviceIdentification() {
        let defaultDevice = AudioInputDevice.systemDefault
        XCTAssertNil(defaultDevice.uid)
        XCTAssertEqual(defaultDevice.id, "__system_default__")
        XCTAssertEqual(defaultDevice.name, "System Default")

        let customDevice = AudioInputDevice(uid: "mic-123", name: "USB Mic")
        XCTAssertEqual(customDevice.uid, "mic-123")
        XCTAssertEqual(customDevice.id, "mic-123")
        XCTAssertEqual(customDevice.name, "USB Mic")
    }
}
