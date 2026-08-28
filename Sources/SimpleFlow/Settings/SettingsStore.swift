import Foundation

public final class SettingsStore {
    private enum Keys {
        static let baseURL = "simpleflow.baseURL"
        static let model = "simpleflow.model"
        static let microphoneDeviceUID = "simpleflow.microphoneDeviceUID"
        static let hotkey = "simpleflow.hotkey"
        static let launchAtLogin = "simpleflow.launchAtLogin"
        static let hasCompletedOnboarding = "simpleflow.hasCompletedOnboarding"
    }

    public static let defaultModel = "gigaam"

    private let userDefaults: UserDefaults
    private let tokenStore: TokenStoring

    public init(
        userDefaults: UserDefaults = .standard,
        tokenStore: TokenStoring = KeychainStore()
    ) {
        self.userDefaults = userDefaults
        self.tokenStore = tokenStore
    }

    public var baseURL: String {
        get {
            userDefaults.string(forKey: Keys.baseURL) ?? ""
        }
        set {
            userDefaults.set(newValue, forKey: Keys.baseURL)
        }
    }

    public var model: String {
        get {
            userDefaults.string(forKey: Keys.model) ?? Self.defaultModel
        }
        set {
            userDefaults.set(newValue, forKey: Keys.model)
        }
    }

    public var microphoneDeviceUID: String? {
        get {
            userDefaults.string(forKey: Keys.microphoneDeviceUID)
        }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: Keys.microphoneDeviceUID)
            } else {
                userDefaults.removeObject(forKey: Keys.microphoneDeviceUID)
            }
        }
    }

    public var hotkey: Hotkey {
        get {
            guard let data = userDefaults.data(forKey: Keys.hotkey),
                  let decoded = try? JSONDecoder().decode(Hotkey.self, from: data) else {
                return .functionKey
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: Keys.hotkey)
            }
        }
    }

    public var launchAtLogin: Bool {
        get {
            userDefaults.bool(forKey: Keys.launchAtLogin)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.launchAtLogin)
        }
    }

    public var hasCompletedOnboarding: Bool {
        get {
            userDefaults.bool(forKey: Keys.hasCompletedOnboarding)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.hasCompletedOnboarding)
        }
    }

    // MARK: - Token Operations

    public func readToken() throws -> String? {
        try tokenStore.readToken()
    }

    public func saveToken(_ token: String) throws {
        try tokenStore.writeToken(token)
    }

    public func writeToken(_ token: String) throws {
        try saveToken(token)
    }

    public func deleteToken() throws {
        try tokenStore.deleteToken()
    }

    // MARK: - Configuration Assembly

    public func transcriptionConfiguration() throws -> TranscriptionConfiguration {
        guard let token = try tokenStore.readToken(),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionConfigurationError.missingToken
        }

        let configuration = TranscriptionConfiguration(
            baseURL: baseURL,
            token: token,
            model: model
        )
        try configuration.validate()
        return configuration
    }
}
