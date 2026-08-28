import CoreGraphics
import XCTest
@testable import SimpleFlow

final class InMemoryTokenStore: TokenStoring {
    var storedToken: String?
    var readCallCount = 0
    var writeCallCount = 0
    var deleteCallCount = 0

    init(initialToken: String? = nil) {
        self.storedToken = initialToken
    }

    func readToken() throws -> String? {
        readCallCount += 1
        return storedToken
    }

    func writeToken(_ token: String) throws {
        writeCallCount += 1
        storedToken = token
    }

    func deleteToken() throws {
        deleteCallCount += 1
        storedToken = nil
    }
}

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var tokenStore: InMemoryTokenStore!

    override func setUp() {
        super.setUp()
        suiteName = "dev.kirill.simpleflow.tests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        tokenStore = InMemoryTokenStore()
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        tokenStore = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - TranscriptionConfiguration Tests

    func testEndpointAppendsAudioTranscriptionsToV1Base() throws {
        let value = TranscriptionConfiguration(
            baseURL: "https://stt.example/v1/",
            token: "secret",
            model: "gigaam"
        )
        XCTAssertEqual(
            try value.validatedEndpoint().absoluteString,
            "https://stt.example/v1/audio/transcriptions"
        )
    }

    func testEndpointAppendsAudioTranscriptionsWithoutTrailingSlash() throws {
        let value = TranscriptionConfiguration(
            baseURL: "https://stt.example/v1",
            token: "secret",
            model: "gigaam"
        )
        XCTAssertEqual(
            try value.validatedEndpoint().absoluteString,
            "https://stt.example/v1/audio/transcriptions"
        )
    }

    func testEndpointWithAlreadyFullTranscriptionsPath() throws {
        let value = TranscriptionConfiguration(
            baseURL: "https://stt.example/v1/audio/transcriptions",
            token: "secret",
            model: "gigaam"
        )
        XCTAssertEqual(
            try value.validatedEndpoint().absoluteString,
            "https://stt.example/v1/audio/transcriptions"
        )
    }

    func testValidatedBaseURLNormalizesURL() throws {
        let value = TranscriptionConfiguration(
            baseURL: "https://stt.example/v1/ ",
            token: "secret",
            model: "gigaam"
        )
        XCTAssertEqual(
            try value.validatedBaseURL().absoluteString,
            "https://stt.example/v1"
        )
    }

    func testMissingTokenIsRejected() {
        let value = TranscriptionConfiguration(baseURL: "https://stt.example/v1", token: "", model: "gigaam")
        XCTAssertThrowsError(try value.validate())
    }

    func testWhitespaceOnlyTokenIsRejected() {
        let value = TranscriptionConfiguration(baseURL: "https://stt.example/v1", token: "   \t\n", model: "gigaam")
        XCTAssertThrowsError(try value.validate())
    }

    func testMissingModelIsRejected() {
        let value = TranscriptionConfiguration(baseURL: "https://stt.example/v1", token: "secret", model: "")
        XCTAssertThrowsError(try value.validate())
    }

    func testWhitespaceOnlyModelIsRejected() {
        let value = TranscriptionConfiguration(baseURL: "https://stt.example/v1", token: "secret", model: "  ")
        XCTAssertThrowsError(try value.validate())
    }

    func testInvalidURLIsRejected() {
        let empty = TranscriptionConfiguration(baseURL: "", token: "secret", model: "gigaam")
        XCTAssertThrowsError(try empty.validate())

        let notAURL = TranscriptionConfiguration(baseURL: "invalid url with spaces", token: "secret", model: "gigaam")
        XCTAssertThrowsError(try notAURL.validate())

        let noScheme = TranscriptionConfiguration(baseURL: "stt.example/v1", token: "secret", model: "gigaam")
        XCTAssertThrowsError(try noScheme.validate())

        let invalidScheme = TranscriptionConfiguration(baseURL: "ftp://stt.example/v1", token: "secret", model: "gigaam")
        XCTAssertThrowsError(try invalidScheme.validate())
    }

    // MARK: - SettingsStore Defaults & Persistence

    func testDefaultValues() {
        let store = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)
        XCTAssertEqual(store.baseURL, "")
        XCTAssertEqual(store.model, "gigaam")
        XCTAssertNil(store.microphoneDeviceUID)
        XCTAssertEqual(store.hotkey, Hotkey.functionKey)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func testPersistsPrimitiveSettingsInUserDefaults() {
        let store = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)
        store.baseURL = "https://custom.api.com/v1"
        store.model = "whisper-1"
        store.microphoneDeviceUID = "BuiltInMicrophoneDevice"
        store.launchAtLogin = true
        store.hasCompletedOnboarding = true

        let customHotkey = Hotkey(
            keyCode: 49,
            modifiersRawValue: CGEventFlags.maskCommand.rawValue,
            isFunctionKeyOnly: false
        )
        store.hotkey = customHotkey

        // Recreate store using same userDefaults suite
        let reloadedStore = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)
        XCTAssertEqual(reloadedStore.baseURL, "https://custom.api.com/v1")
        XCTAssertEqual(reloadedStore.model, "whisper-1")
        XCTAssertEqual(reloadedStore.microphoneDeviceUID, "BuiltInMicrophoneDevice")
        XCTAssertEqual(reloadedStore.hotkey, customHotkey)
        XCTAssertTrue(reloadedStore.launchAtLogin)
        XCTAssertTrue(reloadedStore.hasCompletedOnboarding)
    }

    // MARK: - Token Security

    func testTokenNeverStoredInUserDefaults() throws {
        let store = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)
        let secretToken = "super-secret-key-12345"
        try store.saveToken(secretToken)

        // Verify token can be read back from store
        XCTAssertEqual(try store.readToken(), secretToken)
        XCTAssertEqual(tokenStore.storedToken, secretToken)

        // Verify token is NOT anywhere in userDefaults
        let dict = userDefaults.dictionaryRepresentation()
        for (key, value) in dict {
            XCTAssertFalse(
                key.lowercased().contains("token"),
                "UserDefaults key should not contain 'token': \(key)"
            )
            if let stringValue = value as? String {
                XCTAssertFalse(
                    stringValue.contains(secretToken),
                    "UserDefaults string value should not contain secret token"
                )
            }
        }

        // Delete token
        try store.deleteToken()
        XCTAssertNil(try store.readToken())
        XCTAssertNil(tokenStore.storedToken)
    }

    // MARK: - TranscriptionConfiguration Assembly

    func testTranscriptionConfigurationAssemblySuccess() throws {
        let store = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)
        store.baseURL = "https://api.openai.com/v1"
        store.model = "whisper-1"
        try store.saveToken("sk-test-token")

        let config = try store.transcriptionConfiguration()
        XCTAssertEqual(config.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(config.token, "sk-test-token")
        XCTAssertEqual(config.model, "whisper-1")
        XCTAssertEqual(
            try config.validatedEndpoint().absoluteString,
            "https://api.openai.com/v1/audio/transcriptions"
        )
    }

    func testTranscriptionConfigurationAssemblyThrowsWhenTokenMissing() {
        let store = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)
        store.baseURL = "https://api.openai.com/v1"
        store.model = "whisper-1"
        // Token not saved

        XCTAssertThrowsError(try store.transcriptionConfiguration())
    }

    func testTranscriptionConfigurationAssemblyThrowsWhenBaseURLInvalid() throws {
        let store = SettingsStore(userDefaults: userDefaults, tokenStore: tokenStore)
        store.baseURL = "invalid_url"
        store.model = "whisper-1"
        try store.saveToken("sk-test-token")

        XCTAssertThrowsError(try store.transcriptionConfiguration())
    }
}

final class KeychainStoreTests: XCTestCase {
    private var keychainStore: KeychainStore!
    private var testService: String!
    private var testAccount: String!

    override func setUp() {
        super.setUp()
        testService = "dev.kirill.simpleflow.tests.\(UUID().uuidString)"
        testAccount = "test-token-\(UUID().uuidString)"
        keychainStore = KeychainStore(service: testService, account: testAccount)
    }

    override func tearDown() {
        try? keychainStore.deleteToken()
        keychainStore = nil
        testService = nil
        testAccount = nil
        super.tearDown()
    }

    func testReadWriteUpdateDeleteToken() throws {
        // Initially empty
        XCTAssertNil(try keychainStore.readToken())

        // Write
        let token = "test-token-value-12345"
        try keychainStore.writeToken(token)
        XCTAssertEqual(try keychainStore.readToken(), token)

        // Overwrite / Update
        let updatedToken = "updated-token-value-67890"
        try keychainStore.writeToken(updatedToken)
        XCTAssertEqual(try keychainStore.readToken(), updatedToken)

        // Delete
        try keychainStore.deleteToken()
        XCTAssertNil(try keychainStore.readToken())

        // Deleting non-existent token succeeds without throwing
        XCTAssertNoThrow(try keychainStore.deleteToken())
    }
}

