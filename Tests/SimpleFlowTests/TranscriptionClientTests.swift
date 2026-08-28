import XCTest
@testable import SimpleFlow

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    static var requestHandler: Handler?
    static var lastCapturedRequest: URLRequest?
    static var lastCapturedBody: Data?

    static func reset() {
        requestHandler = nil
        lastCapturedRequest = nil
        lastCapturedBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.lastCapturedRequest = request
        MockURLProtocol.lastCapturedBody = extractBodyData(from: request)

        guard let handler = MockURLProtocol.requestHandler else {
            let error = URLError(.badURL)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func extractBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}

// MARK: - Async Assertion Helper

func XCTAssertThrowsAsyncError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown but expression succeeded. \(message())", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

// MARK: - TranscriptionClientTests

final class TranscriptionClientTests: XCTestCase {
    private var fixtureWAV: URL!
    private var configuration: TranscriptionConfiguration!
    private var client: TranscriptionClient!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        client = TranscriptionClient(session: session)
        configuration = TranscriptionConfiguration(
            baseURL: "https://api.openai.com/v1",
            token: "secret-token",
            model: "gigaam"
        )

        let tempDir = FileManager.default.temporaryDirectory
        fixtureWAV = tempDir.appendingPathComponent("fixture-\(UUID().uuidString).wav")
        let dummyWAVContent = "RIFF\u{24}\u{00}\u{00}\u{00}WAVEfmt \u{10}\u{00}\u{00}\u{00}\u{01}\u{00}\u{01}\u{00}\u{80}\u{3E}\u{00}\u{00}\u{00}\u{7D}\u{00}\u{00}\u{02}\u{00}\u{10}\u{00}data\u{00}\u{00}\u{00}\u{00}"
        try? dummyWAVContent.data(using: .utf8)?.write(to: fixtureWAV)
    }

    override func tearDown() {
        if let fixtureWAV {
            try? FileManager.default.removeItem(at: fixtureWAV)
        }
        MockURLProtocol.reset()
        session = nil
        client = nil
        configuration = nil
        fixtureWAV = nil
        super.tearDown()
    }

    private func stub(status: Int, json: String, headers: [String: String] = [:]) {
        MockURLProtocol.requestHandler = { request in
            var responseHeaders = headers
            responseHeaders["Content-Type"] = "application/json"
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: responseHeaders
            )!
            return (response, json.data(using: .utf8)!)
        }
    }

    private func stubError(_ error: Error) {
        MockURLProtocol.requestHandler = { _ in
            throw error
        }
    }

    // MARK: - Transcribe Tests

    func testTranscribeBuildsAuthorizedOpenAIRequest() async throws {
        stub(status: 200, json: #"{"text":"Распознанный текст"}"#)

        let text = try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)
        XCTAssertEqual(text, "Распознанный текст")

        let capturedRequest = MockURLProtocol.lastCapturedRequest
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(capturedRequest?.url?.path, "/v1/audio/transcriptions")

        // Ensure token is not in URL
        XCTAssertFalse(capturedRequest?.url?.absoluteString.contains("secret-token") ?? true)

        // Ensure Content-Type header is multipart/form-data
        let contentType = capturedRequest?.value(forHTTPHeaderField: "Content-Type")
        XCTAssertTrue(contentType?.starts(with: "multipart/form-data; boundary=") ?? false)

        // Ensure body data contains expected parts
        let capturedBody = MockURLProtocol.lastCapturedBody
        XCTAssertNotNil(capturedBody)
        if let bodyData = capturedBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            XCTAssertTrue(bodyString.contains("name=\"model\""))
            XCTAssertTrue(bodyString.contains("gigaam"))
            XCTAssertTrue(bodyString.contains("name=\"response_format\""))
            XCTAssertTrue(bodyString.contains("json"))
            XCTAssertTrue(bodyString.contains("name=\"file\"; filename=\"audio.wav\""))
        }
    }

    func testEmptyTextThrowsNoSpeech() async {
        stub(status: 200, json: #"{"text":"   "}"#)
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .noSpeech)
        }
    }

    func testEmptyStringThrowsNoSpeech() async {
        stub(status: 200, json: #"{"text":""}"#)
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .noSpeech)
        }
    }

    func testTranscribeUnauthorized401ThrowsUnauthorized() async {
        stub(status: 401, json: #"{"error":"Invalid API key"}"#)
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .unauthorized)
        }
    }

    func testTranscribeForbidden403ThrowsUnauthorized() async {
        stub(status: 403, json: #"{"error":"Forbidden"}"#)
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .unauthorized)
        }
    }

    func testTranscribeServerError500ThrowsServerStatus() async {
        stub(status: 500, json: #"{"error":"Internal server error"}"#)
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .server(status: 500))
        }
    }

    func testTranscribeBadGateway502ThrowsServerStatus() async {
        stub(status: 502, json: #"Bad Gateway"#)
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .server(status: 502))
        }
    }

    func testTranscribeTimeoutThrowsTransportError() async {
        stubError(URLError(.timedOut))
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .transport(.timedOut))
        }
    }

    func testTranscribeNetworkConnectionLostThrowsTransportError() async {
        stubError(URLError(.networkConnectionLost))
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .transport(.networkConnectionLost))
        }
    }

    func testTranscribeMalformedJSONThrowsMalformedResponse() async {
        stub(status: 200, json: #"not valid json"#)
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .malformedResponse)
        }
    }

    func testTranscribeMissingTextFieldThrowsMalformedResponse() async {
        stub(status: 200, json: #"{"other_field":"hello"}"#)
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .malformedResponse)
        }
    }

    func testTranscribeMissingFileThrowsFileUnavailable() async {
        let nonExistentURL = FileManager.default.temporaryDirectory.appendingPathComponent("non-existent-\(UUID().uuidString).wav")
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: nonExistentURL, configuration: configuration)) { error in
            XCTAssertEqual(error as? TranscriptionError, .fileUnavailable)
        }
    }

    func testTranscribeInvalidConfigurationThrowsInvalidConfiguration() async {
        let invalidConfig = TranscriptionConfiguration(baseURL: "not-a-valid-url", token: "secret", model: "gigaam")
        await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: invalidConfig)) { error in
            guard case .invalidConfiguration = (error as? TranscriptionError) else {
                XCTFail("Expected invalidConfiguration error, got \(error)")
                return
            }
        }
    }

    // MARK: - testConnection Tests

    func testConnectionReachableOn200() async {
        stub(status: 200, json: #"{"data":[{"id":"model-1"}]}"#)
        let result = await client.testConnection(configuration: configuration)
        XCTAssertEqual(result, .reachable)

        let capturedRequest = MockURLProtocol.lastCapturedRequest
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(capturedRequest?.url?.path, "/v1/models")
        XCTAssertFalse(capturedRequest?.url?.absoluteString.contains("secret-token") ?? true)
    }

    func testConnectionUnauthorizedOn401() async {
        stub(status: 401, json: #"{"error":"Unauthorized"}"#)
        let result = await client.testConnection(configuration: configuration)
        XCTAssertEqual(result, .unauthorized)
    }

    func testConnectionUnauthorizedOn403() async {
        stub(status: 403, json: #"{"error":"Forbidden"}"#)
        let result = await client.testConnection(configuration: configuration)
        XCTAssertEqual(result, .unauthorized)
    }

    func testConnectionModelsEndpointUnsupportedOn404() async {
        stub(status: 404, json: #"{"error":"Not Found"}"#)
        let result = await client.testConnection(configuration: configuration)
        XCTAssertEqual(result, .modelsEndpointUnsupported)
    }

    func testConnectionModelsEndpointUnsupportedOn405() async {
        stub(status: 405, json: #"{"error":"Method Not Allowed"}"#)
        let result = await client.testConnection(configuration: configuration)
        XCTAssertEqual(result, .modelsEndpointUnsupported)
    }

    func testConnectionServerErrorOn500() async {
        stub(status: 500, json: #"{"error":"Internal error"}"#)
        let result = await client.testConnection(configuration: configuration)
        XCTAssertEqual(result, .server(status: 500))
    }

    func testConnectionTransportErrorOnTimeout() async {
        stubError(URLError(.timedOut))
        let result = await client.testConnection(configuration: configuration)
        XCTAssertEqual(result, .transport(.timedOut))
    }

    func testConnectionInvalidConfiguration() async {
        let invalidConfig = TranscriptionConfiguration(baseURL: "invalid-url", token: "secret", model: "gigaam")
        let result = await client.testConnection(configuration: invalidConfig)
        guard case .invalidConfiguration = result else {
            XCTFail("Expected .invalidConfiguration, got \(result)")
            return
        }
    }

    func testConnectionWithFullEndpointPathInBaseURL() async {
        let configWithFullPath = TranscriptionConfiguration(
            baseURL: "https://api.openai.com/v1/audio/transcriptions",
            token: "secret-token",
            model: "gigaam"
        )
        stub(status: 200, json: #"{"data":[]}"#)
        let result = await client.testConnection(configuration: configWithFullPath)
        XCTAssertEqual(result, .reachable)

        let capturedRequest = MockURLProtocol.lastCapturedRequest
        XCTAssertEqual(capturedRequest?.url?.path, "/v1/models")
    }

    func testGigaAMTranscribeSuccess() async throws {
        let gigaConfig = TranscriptionConfiguration(
            baseURL: "https://stt.iqdoc.ai",
            token: "giga-secret-token",
            model: "v3_e2e_rnnt"
        )
        XCTAssertTrue(gigaConfig.isGigaAM)

        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "giga-secret-token")
                XCTAssertEqual(request.url?.path, "/api/v1/transcribe")
                let json = #"{"task_id":"task-123","message":"Uploaded","filename":"audio.wav","file_size":100}"#
                let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
                return (response, json.data(using: .utf8)!)
            } else if request.httpMethod == "GET" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "giga-secret-token")
                XCTAssertEqual(request.url?.path, "/api/v1/tasks/task-123/result")
                let json = #"{"task_id":"task-123","status":"completed","filename":"audio.wav","transcription":"Привет мир"}"#
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, json.data(using: .utf8)!)
            } else if request.httpMethod == "DELETE" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            throw URLError(.badServerResponse)
        }

        let result = try await client.transcribe(fileURL: fixtureWAV, configuration: gigaConfig)
        XCTAssertEqual(result, "Привет мир")
    }

    func testGigaAMTestConnectionReachable() async {
        let gigaConfig = TranscriptionConfiguration(
            baseURL: "https://stt.iqdoc.ai",
            token: "giga-secret-token",
            model: "v3_e2e_rnnt"
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "giga-secret-token")
            XCTAssertEqual(request.url?.path, "/api/v1/asr/options")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let result = await client.testConnection(configuration: gigaConfig)
        XCTAssertEqual(result, .reachable)
    }
}

