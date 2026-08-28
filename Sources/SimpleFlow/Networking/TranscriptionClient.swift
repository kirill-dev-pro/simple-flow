import Foundation

public protocol Transcribing: Sendable {
    func transcribe(fileURL: URL, configuration: TranscriptionConfiguration) async throws -> String
    func testConnection(configuration: TranscriptionConfiguration) async -> ConnectionTestResult
}

extension Transcribing {
    public func testConnection(configuration: TranscriptionConfiguration) async -> ConnectionTestResult {
        .reachable
    }
}

public enum TranscriptionError: Error, Equatable, LocalizedError {
    case invalidConfiguration(String)
    case fileUnavailable
    case unauthorized
    case server(status: Int)
    case transport(URLError.Code)
    case malformedResponse
    case noSpeech

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "Invalid transcription configuration: \(reason)"
        case .fileUnavailable:
            return "Audio file is unavailable or unreadable."
        case .unauthorized:
            return "Unauthorized. Please check your API token."
        case .server(let status):
            return "Server error (status \(status))."
        case .transport(let code):
            return "Network transport error (\(code.rawValue))."
        case .malformedResponse:
            return "Malformed response from transcription server."
        case .noSpeech:
            return "No speech detected in audio."
        }
    }
}

public enum ConnectionTestResult: Equatable {
    case reachable
    case unauthorized
    case modelsEndpointUnsupported
    case server(status: Int)
    case transport(URLError.Code)
    case invalidConfiguration(String)
}

public final class TranscriptionClient: Transcribing {
    private let session: URLSession

    public init(session: URLSession = TranscriptionClient.createDefaultSession()) {
        self.session = session
    }

    public static func createDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    public func transcribe(fileURL: URL, configuration: TranscriptionConfiguration) async throws -> String {
        let endpoint: URL
        do {
            try configuration.validate()
            endpoint = try configuration.validatedEndpoint()
        } catch {
            AppLogger.network.error("Transcribe configuration validation failed: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionError.invalidConfiguration(error.localizedDescription)
        }

        guard let fileData = try? Data(contentsOf: fileURL), !fileData.isEmpty else {
            AppLogger.network.error("Transcribe failed: audio file unavailable or empty")
            throw TranscriptionError.fileUnavailable
        }

        AppLogger.network.info("Starting transcribe request (model: \(configuration.model, privacy: .public), payload size: \(fileData.count) bytes)")

        let (bodyData, contentType, _) = MultipartFormData.createTranscriptionBody(
            model: configuration.model,
            fileData: fileData
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.upload(for: request, from: bodyData)
        } catch let urlError as URLError {
            AppLogger.network.error("Transcribe network transport error: \(urlError.code.rawValue)")
            throw TranscriptionError.transport(urlError.code)
        } catch {
            AppLogger.network.error("Transcribe unknown transport error")
            throw TranscriptionError.transport(.unknown)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.network.error("Transcribe failed: non-HTTP response received")
            throw TranscriptionError.malformedResponse
        }

        AppLogger.network.info("Transcribe HTTP response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...299:
            struct ResponsePayload: Decodable {
                let text: String
            }
            guard let decoded = try? JSONDecoder().decode(ResponsePayload.self, from: responseData) else {
                AppLogger.network.error("Transcribe failed: malformed JSON response")
                throw TranscriptionError.malformedResponse
            }
            let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                AppLogger.network.warning("Transcribe completed with empty speech text")
                throw TranscriptionError.noSpeech
            }
            AppLogger.network.info("Transcribe succeeded (length: \(trimmed.count) characters)")
            return trimmed
        case 401, 403:
            AppLogger.network.error("Transcribe failed: unauthorized (\(httpResponse.statusCode))")
            throw TranscriptionError.unauthorized
        default:
            AppLogger.network.error("Transcribe failed: server error (\(httpResponse.statusCode))")
            throw TranscriptionError.server(status: httpResponse.statusCode)
        }
    }

    public func testConnection(configuration: TranscriptionConfiguration) async -> ConnectionTestResult {
        AppLogger.network.info("Starting connection test")
        let modelsURL: URL
        do {
            try configuration.validate()
            let base = try configuration.validatedBaseURL()
            if base.path.hasSuffix("/audio/transcriptions") {
                modelsURL = base.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("models")
            } else {
                modelsURL = base.appendingPathComponent("models")
            }
        } catch {
            let result = ConnectionTestResult.invalidConfiguration(error.localizedDescription)
            AppLogger.network.error("Connection test failed configuration validation: \(error.localizedDescription, privacy: .public)")
            return result
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            let result = ConnectionTestResult.transport(urlError.code)
            AppLogger.network.error("Connection test transport error: \(urlError.code.rawValue)")
            return result
        } catch {
            let result = ConnectionTestResult.transport(.unknown)
            AppLogger.network.error("Connection test unknown transport error")
            return result
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let result = ConnectionTestResult.server(status: -1)
            AppLogger.network.error("Connection test non-HTTP response")
            return result
        }

        AppLogger.network.info("Connection test HTTP response status: \(httpResponse.statusCode)")

        let result: ConnectionTestResult
        switch httpResponse.statusCode {
        case 200...299:
            result = .reachable
        case 401, 403:
            result = .unauthorized
        case 404, 405:
            result = .modelsEndpointUnsupported
        default:
            result = .server(status: httpResponse.statusCode)
        }
        AppLogger.network.info("Connection test finished with result: \(String(describing: result), privacy: .public)")
        return result
    }
}
