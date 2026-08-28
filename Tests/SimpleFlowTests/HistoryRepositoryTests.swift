import Foundation
import SwiftData
import XCTest
@testable import SimpleFlow

@MainActor
final class HistoryRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repository: HistoryRepository!

    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: TranscriptRecord.self, configurations: configuration)
        context = ModelContext(container)
        repository = HistoryRepository(context: context)
    }

    override func tearDown() async throws {
        repository = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func testSuccessfulTranscriptsSortNewestFirst() throws {
        try repository.save(
            text: "older",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceApplicationName: "TextEdit",
            insertionStatus: .inserted
        )
        try repository.save(
            text: "newer",
            createdAt: Date(timeIntervalSince1970: 2),
            sourceApplicationName: "Safari",
            insertionStatus: .focusChanged
        )

        let records = try repository.fetchAll()
        XCTAssertEqual(records.map(\.text), ["newer", "older"])
        XCTAssertEqual(records[0].sourceApplicationName, "Safari")
        XCTAssertEqual(records[0].insertionStatus, .focusChanged)
        XCTAssertEqual(records[1].sourceApplicationName, "TextEdit")
        XCTAssertEqual(records[1].insertionStatus, .inserted)
    }

    func testRejectsEmptyOrWhitespaceOnlyText() throws {
        XCTAssertThrowsError(try repository.save(text: "", createdAt: Date(), sourceApplicationName: nil, insertionStatus: .inserted)) { error in
            XCTAssertEqual(error as? HistoryError, .emptyText)
        }

        XCTAssertThrowsError(try repository.save(text: "   \n\t  ", createdAt: Date(), sourceApplicationName: nil, insertionStatus: .inserted)) { error in
            XCTAssertEqual(error as? HistoryError, .emptyText)
        }

        let records = try repository.fetchAll()
        XCTAssertTrue(records.isEmpty)
    }

    func testSavePersistsRecordAndReturnsInstance() throws {
        let date = Date(timeIntervalSince1970: 100)
        let record = try repository.save(
            text: "Hello world",
            createdAt: date,
            sourceApplicationName: "Notes",
            insertionStatus: .inserted
        )

        XCTAssertEqual(record.text, "Hello world")
        XCTAssertEqual(record.createdAt, date)
        XCTAssertEqual(record.sourceApplicationName, "Notes")
        XCTAssertEqual(record.insertionStatus, .inserted)
        XCTAssertEqual(record.insertionStatusRawValue, "inserted")

        let fetched = try repository.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, record.id)
        XCTAssertEqual(fetched.first?.text, "Hello world")
    }

    func testUpdateInsertionStatus() throws {
        let record = try repository.save(
            text: "Draft message",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceApplicationName: "Slack",
            insertionStatus: .focusChanged
        )

        XCTAssertEqual(record.insertionStatus, .focusChanged)
        try repository.updateInsertionStatus(record, to: .pasteFailed)

        let fetched = try repository.fetchAll()
        XCTAssertEqual(fetched.first?.insertionStatus, .pasteFailed)
        XCTAssertEqual(fetched.first?.insertionStatusRawValue, "pasteFailed")
    }

    func testDeleteRecord() throws {
        let first = try repository.save(text: "First", createdAt: Date(timeIntervalSince1970: 10), sourceApplicationName: nil, insertionStatus: .inserted)
        let second = try repository.save(text: "Second", createdAt: Date(timeIntervalSince1970: 20), sourceApplicationName: nil, insertionStatus: .inserted)

        try repository.delete(first)

        let records = try repository.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, second.id)
    }

    func testClearHistory() throws {
        try repository.save(text: "One", createdAt: Date(timeIntervalSince1970: 1), sourceApplicationName: nil, insertionStatus: .inserted)
        try repository.save(text: "Two", createdAt: Date(timeIntervalSince1970: 2), sourceApplicationName: nil, insertionStatus: .inserted)
        try repository.save(text: "Three", createdAt: Date(timeIntervalSince1970: 3), sourceApplicationName: nil, insertionStatus: .inserted)

        XCTAssertEqual(try repository.fetchAll().count, 3)

        try repository.clear()

        XCTAssertTrue(try repository.fetchAll().isEmpty)
    }

    func testTranscriptRecordFallbackStatusWhenRawValueIsUnknown() {
        let record = TranscriptRecord(
            text: "Unknown status",
            createdAt: Date(),
            sourceApplicationName: nil,
            insertionStatus: .inserted
        )
        record.insertionStatusRawValue = "some_future_status"
        XCTAssertEqual(record.insertionStatus, .pasteFailed)
    }
}
