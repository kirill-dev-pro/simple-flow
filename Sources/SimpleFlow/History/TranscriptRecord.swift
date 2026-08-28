import Foundation
import SwiftData

public enum InsertionStatus: String, Codable, CaseIterable, Sendable {
    case inserted
    case focusChanged
    case pasteFailed
}

@Model
public final class TranscriptRecord {
    @Attribute(.unique) public var id: UUID
    public var text: String
    public var createdAt: Date
    public var sourceApplicationName: String?
    public var insertionStatusRawValue: String

    public var insertionStatus: InsertionStatus {
        get { InsertionStatus(rawValue: insertionStatusRawValue) ?? .pasteFailed }
        set { insertionStatusRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        sourceApplicationName: String? = nil,
        insertionStatus: InsertionStatus = .inserted
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.sourceApplicationName = sourceApplicationName
        self.insertionStatusRawValue = insertionStatus.rawValue
    }
}
