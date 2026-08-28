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
            throw TranscriptionError.invalidConfiguration(error.localizedDescription)
        }

        guard let fileData = try? Data(contentsOf: fileURL), !fileData.isEmpty else {
            throw TranscriptionError.fileUnavailable
        }

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
            throw TranscriptionError.transport(urlError.code)
        } catch {
            throw TranscriptionError.transport(.unknown)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.malformedResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            struct ResponsePayload: Decodable {
                let text: String
            }
            guard let decoded = try? JSONDecoder().decode(ResponsePayload.self, from: responseData) else {
                throw TranscriptionError.malformedResponse
            }
            let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw TranscriptionError.noSpeech
            }
            return trimmed
        case 401, 403:
            throw TranscriptionError.unauthorized
        default:
            throw TranscriptionError.server(status: httpResponse.statusCode)
        }
    }

    public func testConnection(configuration: TranscriptionConfiguration) async -> ConnectionTestResult {
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
            return .invalidConfiguration(error.localizedDescription)
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            return .transport(urlError.code)
        } catch {
            return .transport(.unknown)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .server(status: -1)
        }

        switch httpResponse.statusCode {
        case 200...299:
            return .reachable
        case 401, 403:
            return .unauthorized
        case 404, 405:
            return .modelsEndpointUnsupported
        default:
            return .server(status: httpResponse.statusCode)
        }
    }
}
