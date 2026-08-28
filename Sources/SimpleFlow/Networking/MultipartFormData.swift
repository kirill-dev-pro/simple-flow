import Foundation

public struct MultipartFormData: Sendable {
    public let boundary: String
    private var body = Data()

    public init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public mutating func addField(name: String, value: String) {
        var part = Data()
        part.append("--\(boundary)\r\n".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        part.append("\(value)\r\n".data(using: .utf8)!)
        body.append(part)
    }

    public mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        var part = Data()
        part.append("--\(boundary)\r\n".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        part.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        part.append(data)
        part.append("\r\n".data(using: .utf8)!)
        body.append(part)
    }

    public func build() -> Data {
        var finalized = body
        finalized.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return finalized
    }

    public static func createTranscriptionBody(
        model: String,
        fileData: Data,
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) -> (data: Data, contentType: String, boundary: String) {
        var form = MultipartFormData(boundary: boundary)
        form.addField(name: "model", value: model)
        form.addField(name: "response_format", value: "json")
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: fileData)
        return (form.build(), form.contentType, boundary)
    }

    public static func createGigaAMTranscriptionBody(
        fileData: Data,
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) -> (data: Data, contentType: String, boundary: String) {
        var form = MultipartFormData(boundary: boundary)
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: fileData)
        return (form.build(), form.contentType, boundary)
    }
}
