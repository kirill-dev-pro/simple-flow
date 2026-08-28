import AppKit
import XCTest
@testable import SimpleFlow

final class PasteboardClientTests: XCTestCase {
    func testEmptyPasteboardSnapshotAndRestore() {
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        let client = PasteboardClient(pasteboard: pasteboard)

        let snapshot = client.snapshot()
        XCTAssertTrue(snapshot.items.isEmpty)

        let insertedCount = client.writeString("temporary transcript")
        XCTAssertEqual(pasteboard.string(forType: .string), "temporary transcript")

        let restored = client.restore(snapshot, matchingChangeCount: insertedCount)
        XCTAssertTrue(restored)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testSnapshotCapturesAllItemsAndTypesAndRestores() {
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        let client = PasteboardClient(pasteboard: pasteboard)

        pasteboard.clearContents()
        let item1 = NSPasteboardItem()
        item1.setString("hello world", forType: .string)
        item1.setData(Data([0x01, 0x02, 0x03]), forType: .init("custom.binary.type"))

        let item2 = NSPasteboardItem()
        item2.setString("second item", forType: .string)

        pasteboard.writeObjects([item1, item2])

        let snapshot = client.snapshot()
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].representations[.string], "hello world".data(using: .utf8))
        XCTAssertEqual(snapshot.items[0].representations[.init("custom.binary.type")], Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(snapshot.items[1].representations[.string], "second item".data(using: .utf8))

        let insertedCount = client.writeString("transcribed text")
        XCTAssertEqual(pasteboard.string(forType: .string), "transcribed text")
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)

        let restored = client.restore(snapshot, matchingChangeCount: insertedCount)
        XCTAssertTrue(restored)

        let restoredItems = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(restoredItems.count, 2)
        XCTAssertEqual(restoredItems[0].string(forType: .string), "hello world")
        XCTAssertEqual(restoredItems[0].data(forType: .init("custom.binary.type")), Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(restoredItems[1].string(forType: .string), "second item")
    }

    func testRestorationSkippedWhenUserModifiesPasteboard() {
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        let client = PasteboardClient(pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("original content", forType: .string)
        let snapshot = client.snapshot()

        let insertedCount = client.writeString("transcribed text")
        XCTAssertEqual(pasteboard.string(forType: .string), "transcribed text")

        // User copies something else in another application
        pasteboard.clearContents()
        pasteboard.setString("user's new copy", forType: .string)

        let restored = client.restore(snapshot, matchingChangeCount: insertedCount)
        XCTAssertFalse(restored)
        XCTAssertEqual(pasteboard.string(forType: .string), "user's new copy")
    }

    func testWriteTranscriptIncrementsChangeCount() {
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        let client = PasteboardClient(pasteboard: pasteboard)

        let countBefore = client.changeCount
        let insertedCount = client.writeString("sample text")

        XCTAssertEqual(insertedCount, client.changeCount)
        XCTAssertGreaterThan(insertedCount, countBefore)
    }
}
