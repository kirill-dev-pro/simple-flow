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

        return PasteboardSnapshot(items: itemSnapshots)
    }

    @discardableResult
    public func writeString(_ text: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    @discardableResult
    public func restore(_ snapshot: PasteboardSnapshot, matchingChangeCount expectedChangeCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else {
            return false
        }

        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else {
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

        return true
    }
}
