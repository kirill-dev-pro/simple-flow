import Foundation

public enum TranscriptionConfigurationError: LocalizedError, Equatable {
    case missingToken
    case missingModel
    case invalidBaseURL(String)
    case invalidEndpoint

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token cannot be empty."
        case .missingModel:
            return "Model name cannot be empty."
        case .invalidBaseURL(let url):
            return "Invalid Base URL: '\(url)'. Must be a valid HTTP or HTTPS URL."
        case .invalidEndpoint:
            return "Could not construct valid transcription endpoint URL."
        }
    }
}

public struct TranscriptionConfiguration: Equatable {
    public let baseURL: String
    public let token: String
    public let model: String

    public init(baseURL: String, token: String, model: String) {
        self.baseURL = baseURL
        self.token = token
        self.model = model
    }

    public var isGigaAM: Bool {
        let lowerURL = baseURL.lowercased()
        return lowerURL.contains("stt.iqdoc.ai") ||
               lowerURL.contains("/api/v1") ||
               lowerURL.hasSuffix("/transcribe")
    }

    public func validate() throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionConfigurationError.missingToken
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionConfigurationError.missingModel
        }
        _ = try validatedBaseURL()
        _ = try validatedEndpoint()
    }

    public func validatedBaseURL() throws -> URL {
        var cleaned = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }

        guard let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            throw TranscriptionConfigurationError.invalidBaseURL(baseURL)
        }

        return url
    }

    public func validatedEndpoint() throws -> URL {
        let base = try validatedBaseURL()
        if isGigaAM {
            if base.path.hasSuffix("/api/v1/transcribe") || base.path == "/api/v1/transcribe" {
                return base
            }
            if base.path.hasSuffix("/api/v1") || base.path == "/api/v1" {
                return base.appendingPathComponent("transcribe")
            }
            return base.appendingPathComponent("api").appendingPathComponent("v1").appendingPathComponent("transcribe")
        } else {
            if base.path.hasSuffix("/audio/transcriptions") || base.path == "/audio/transcriptions" {
                return base
            }
            return base.appendingPathComponent("audio").appendingPathComponent("transcriptions")
        }
    }
}
