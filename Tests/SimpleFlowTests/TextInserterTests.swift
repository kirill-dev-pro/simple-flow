import AppKit
import XCTest
@testable import SimpleFlow

final class FakePasteboardManager: PasteboardManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var internalItems: [PasteboardItemSnapshot] = []
    private var internalChangeCount: Int = 0

    init(initialText: String? = nil) {
        if let text = initialText {
            let repr: [NSPasteboard.PasteboardType: Data] = [.string: text.data(using: .utf8)!]
            self.internalItems = [PasteboardItemSnapshot(representations: repr)]
            self.internalChangeCount = 1
        }
    }

    init(items: [PasteboardItemSnapshot]) {
        self.internalItems = items
        self.internalChangeCount = items.isEmpty ? 0 : 1
    }

    var changeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return internalChangeCount
    }

    func snapshot() -> PasteboardSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return PasteboardSnapshot(items: internalItems)
    }

    @discardableResult
    func writeString(_ text: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        internalChangeCount += 1
        let repr: [NSPasteboard.PasteboardType: Data] = [.string: text.data(using: .utf8)!]
        internalItems = [PasteboardItemSnapshot(representations: repr)]
        return internalChangeCount
    }

    @discardableResult
    func restore(_ snapshot: PasteboardSnapshot, matchingChangeCount expectedChangeCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard internalChangeCount == expectedChangeCount else {
            return false
        }
        internalChangeCount += 1
        internalItems = snapshot.items
        return true
    }

    func currentText() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = internalItems.first?.representations[.string] else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func currentItems() -> [PasteboardItemSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return internalItems
    }
}

final class FakeEventPoster: EventPosting, @unchecked Sendable {
    private let lock = NSLock()
    var shouldSucceed: Bool = true
    private(set) var postCallCount: Int = 0

    init(shouldSucceed: Bool = true) {
        self.shouldSucceed = shouldSucceed
    }

    func postPasteCommand() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        postCallCount += 1
        return shouldSucceed
    }
}

final class FakeRestorationScheduler: PasteRestorationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduledActions: [(delay: TimeInterval, action: @Sendable () -> Void)] = []

    var scheduledCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return scheduledActions.count
    }

    var lastDelay: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return scheduledActions.last?.delay
    }

    func schedule(after delay: TimeInterval, action: @escaping @Sendable () -> Void) {
        lock.lock()
        scheduledActions.append((delay, action))
        lock.unlock()
    }

    func fireAll() {
        lock.lock()
        let actions = scheduledActions.map(\.action)
        scheduledActions.removeAll()
        lock.unlock()
        for action in actions {
            action()
        }
    }
}

final class TextInserterTests: XCTestCase {
    func testDefaultRestorationDelayIsHalfSecond() async {
        let fakePasteboard = FakePasteboardManager(initialText: "clip")
        let fakePoster = FakeEventPoster(shouldSucceed: true)
        let fakeScheduler = FakeRestorationScheduler()

        let inserter = TextInserter(
            pasteboard: fakePasteboard,
            eventPoster: fakePoster,
            scheduler: fakeScheduler
        )

        _ = await inserter.insert("hello")
        XCTAssertEqual(fakeScheduler.lastDelay, 0.5)
        XCTAssertEqual(TextInserter.defaultRestorationDelay, 0.5)
    }

    func testInsertSuccessAndScheduledRestoration() async {
        let fakePasteboard = FakePasteboardManager(initialText: "original user copy")
        let fakePoster = FakeEventPoster(shouldSucceed: true)
        let fakeScheduler = FakeRestorationScheduler()

        let inserter = TextInserter(
            pasteboard: fakePasteboard,
            eventPoster: fakePoster,
            scheduler: fakeScheduler,
            restorationDelay: 0.25
        )

        let result = await inserter.insert("transcribed speech")

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(fakePoster.postCallCount, 1)
        XCTAssertEqual(fakePasteboard.currentText(), "transcribed speech")
        XCTAssertEqual(fakeScheduler.scheduledCount, 1)
        XCTAssertEqual(fakeScheduler.lastDelay, 0.25)

        // Fire restoration
        fakeScheduler.fireAll()
        XCTAssertEqual(fakePasteboard.currentText(), "original user copy")
    }

    func testInsertPreservesUserClipboardWhenUserCopiesBeforeRestoration() async {
        let fakePasteboard = FakePasteboardManager(initialText: "original clipboard")
        let fakePoster = FakeEventPoster(shouldSucceed: true)
        let fakeScheduler = FakeRestorationScheduler()

        let inserter = TextInserter(
            pasteboard: fakePasteboard,
            eventPoster: fakePoster,
            scheduler: fakeScheduler,
            restorationDelay: 0.25
        )

        let result = await inserter.insert("transcribed speech")
        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(fakePasteboard.currentText(), "transcribed speech")

        // User copies new text before the 250ms timer fires
        fakePasteboard.writeString("new user selection")

        fakeScheduler.fireAll()
        XCTAssertEqual(fakePasteboard.currentText(), "new user selection")
    }

    func testInsertReturnsPasteFailedWhenEventPosterFailsAndRestoresClipboard() async {
        let fakePasteboard = FakePasteboardManager(initialText: "original clipboard")
        let fakePoster = FakeEventPoster(shouldSucceed: false)
        let fakeScheduler = FakeRestorationScheduler()

        let inserter = TextInserter(
            pasteboard: fakePasteboard,
            eventPoster: fakePoster,
            scheduler: fakeScheduler,
            restorationDelay: 0.25
        )

        let result = await inserter.insert("transcribed speech")

        XCTAssertEqual(result, .pasteFailed)
        XCTAssertEqual(fakePoster.postCallCount, 1)
        XCTAssertEqual(fakeScheduler.scheduledCount, 0)
        XCTAssertEqual(fakePasteboard.currentText(), "original clipboard")
    }

    func testInsertPreservesMultiItemClipboardOnRestoration() async {
        let item1 = PasteboardItemSnapshot(representations: [
            .string: "first".data(using: .utf8)!,
            .init("custom.type"): Data([0xAA, 0xBB])
        ])
        let item2 = PasteboardItemSnapshot(representations: [
            .string: "second".data(using: .utf8)!
        ])
        let fakePasteboard = FakePasteboardManager(items: [item1, item2])
        let fakePoster = FakeEventPoster(shouldSucceed: true)
        let fakeScheduler = FakeRestorationScheduler()

        let inserter = TextInserter(
            pasteboard: fakePasteboard,
            eventPoster: fakePoster,
            scheduler: fakeScheduler,
            restorationDelay: 0.25
        )

        let result = await inserter.insert("transcribed speech")
        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(fakePasteboard.currentText(), "transcribed speech")

        fakeScheduler.fireAll()

        let items = fakePasteboard.currentItems()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].representations[.string], "first".data(using: .utf8))
        XCTAssertEqual(items[0].representations[.init("custom.type")], Data([0xAA, 0xBB]))
        XCTAssertEqual(items[1].representations[.string], "second".data(using: .utf8))
    }
}
