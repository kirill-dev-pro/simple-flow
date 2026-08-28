import AppKit
import Foundation

public struct PasteboardItemSnapshot: Equatable, Sendable {
    public let representations: [NSPasteboard.PasteboardType: Data]

    public init(representations: [NSPasteboard.PasteboardType: Data] = [:]) {
        self.representations = representations
    }
}

public struct PasteboardSnapshot: Equatable, Sendable {
    public let items: [PasteboardItemSnapshot]

    public init(items: [PasteboardItemSnapshot] = []) {
        self.items = items
    }

    public var isEmpty: Bool {
        items.isEmpty || items.allSatisfy { $0.representations.isEmpty }
    }
}

public protocol PasteboardManaging: Sendable {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    @discardableResult
    func writeString(_ text: String) -> Int
    @discardableResult
    func restore(_ snapshot: PasteboardSnapshot, matchingChangeCount expectedChangeCount: Int) -> Bool
}

public final class PasteboardClient: PasteboardManaging, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public func snapshot() -> PasteboardSnapshot {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            AppLogger.insertion.debug("Captured empty pasteboard snapshot")
            return PasteboardSnapshot(items: [])
        }

        let itemSnapshots = items.map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type] = data
                }
            }
            return PasteboardItemSnapshot(representations: representations)
        }

        AppLogger.insertion.debug("Captured pasteboard snapshot (\(itemSnapshots.count) items)")
        return PasteboardSnapshot(items: itemSnapshots)
    }

    @discardableResult
    public func writeString(_ text: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        AppLogger.insertion.debug("Wrote text to pasteboard (length: \(text.count) characters, changeCount: \(self.pasteboard.changeCount))")
        return pasteboard.changeCount
    }

    @discardableResult
    public func restore(_ snapshot: PasteboardSnapshot, matchingChangeCount expectedChangeCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else {
            AppLogger.insertion.info("Pasteboard restoration skipped: changeCount mismatch (current: \(self.pasteboard.changeCount), expected: \(expectedChangeCount))")
            return false
        }

        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else {
            AppLogger.insertion.debug("Restored empty pasteboard snapshot")
            return true
        }

        let objects: [NSPasteboardItem] = snapshot.items.compactMap { itemSnapshot in
            guard !itemSnapshot.representations.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot.representations {
                item.setData(data, forType: type)
            }
            return item
        }

        if !objects.isEmpty {
            pasteboard.writeObjects(objects)
        }

        AppLogger.insertion.debug("Restored pasteboard snapshot (\(snapshot.items.count) items)")
        return true
    }
}
