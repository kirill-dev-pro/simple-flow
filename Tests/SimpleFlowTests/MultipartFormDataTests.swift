import XCTest
@testable import SimpleFlow

final class MultipartFormDataTests: XCTestCase {
    func testDeterministicMultipartEncodingWithFixedBoundary() {
        let boundary = "test-boundary-12345"
        var form = MultipartFormData(boundary: boundary)
        form.addField(name: "model", value: "gigaam")
        form.addField(name: "response_format", value: "json")

        let fileData = "RIFF1234WAVEfmt ".data(using: .utf8)!
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: fileData)

        let bodyData = form.build()
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            XCTFail("Multipart data should be valid UTF-8 string for text parts")
            return
        }

        let expected = "--test-boundary-12345\r\n" +
            "Content-Disposition: form-data; name=\"model\"\r\n\r\n" +
            "gigaam\r\n" +
            "--test-boundary-12345\r\n" +
            "Content-Disposition: form-data; name=\"response_format\"\r\n\r\n" +
            "json\r\n" +
            "--test-boundary-12345\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n" +
            "Content-Type: audio/wav\r\n\r\n" +
            "RIFF1234WAVEfmt \r\n" +
            "--test-boundary-12345--\r\n"

        XCTAssertEqual(bodyString, expected)
    }

    func testContentTypeHeaderFormat() {
        let form = MultipartFormData(boundary: "my-custom-boundary")
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=my-custom-boundary")
    }

    func testCRLFLineEndingsThroughout() {
        let boundary = "crlf-check-boundary"
        var form = MultipartFormData(boundary: boundary)
        form.addField(name: "testField", value: "testValue")
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: Data([0x01, 0x02, 0x03]))

        let bodyData = form.build()
        let bodyString = String(decoding: bodyData, as: UTF8.self)

        // Ensure every \n in text structure is preceded by \r (CRLF)
        var previousChar: Character?
        for char in bodyString {
            if char == "\n" {
                XCTAssertEqual(previousChar, "\r", "Every newline must be preceded by carriage return (CRLF)")
            }
            previousChar = char
        }
    }

    func testCreateTranscriptionBodyHelper() {
        let boundary = "static-transcription-boundary"
        let audioData = Data([0x52, 0x49, 0x46, 0x46]) // "RIFF"
        let result = MultipartFormData.createTranscriptionBody(
            model: "gigaam",
            fileData: audioData,
            boundary: boundary
        )

        XCTAssertEqual(result.boundary, boundary)
        XCTAssertEqual(result.contentType, "multipart/form-data; boundary=static-transcription-boundary")

        let expectedString = "--static-transcription-boundary\r\n" +
            "Content-Disposition: form-data; name=\"model\"\r\n\r\n" +
            "gigaam\r\n" +
            "--static-transcription-boundary\r\n" +
            "Content-Disposition: form-data; name=\"response_format\"\r\n\r\n" +
            "json\r\n" +
            "--static-transcription-boundary\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n" +
            "Content-Type: audio/wav\r\n\r\n" +
            "RIFF\r\n" +
            "--static-transcription-boundary--\r\n"

        XCTAssertEqual(String(data: result.data, encoding: .utf8), expectedString)
    }
}
