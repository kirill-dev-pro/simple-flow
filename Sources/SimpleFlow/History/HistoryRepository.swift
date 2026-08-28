import Foundation
import SwiftData

public enum HistoryError: Error, Equatable, Sendable {
    case emptyText
}

public protocol HistoryStoring {
    @discardableResult
    func save(
        text: String,
        createdAt: Date,
        sourceApplicationName: String?,
        insertionStatus: InsertionStatus
    ) throws -> TranscriptRecord

    func updateInsertionStatus(_ record: TranscriptRecord, to status: InsertionStatus) throws
    func fetchAll() throws -> [TranscriptRecord]
    func delete(_ record: TranscriptRecord) throws
    func clear() throws
}

extension HistoryStoring {
    @discardableResult
    public func save(
        text: String,
        createdAt: Date = Date(),
        sourceApplicationName: String? = nil,
        insertionStatus: InsertionStatus = .inserted
    ) throws -> TranscriptRecord {
        try save(
            text: text,
            createdAt: createdAt,
            sourceApplicationName: sourceApplicationName,
            insertionStatus: insertionStatus
        )
    }
}

public final class HistoryRepository: HistoryStoring {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func save(
        text: String,
        createdAt: Date,
        sourceApplicationName: String?,
        insertionStatus: InsertionStatus
    ) throws -> TranscriptRecord {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HistoryError.emptyText
        }

        let record = TranscriptRecord(
            text: text,
            createdAt: createdAt,
            sourceApplicationName: sourceApplicationName,
            insertionStatus: insertionStatus
        )
        context.insert(record)
        try context.save()
        return record
    }

    public func updateInsertionStatus(_ record: TranscriptRecord, to status: InsertionStatus) throws {
        record.insertionStatus = status
        try context.save()
    }

    public func fetchAll() throws -> [TranscriptRecord] {
        let descriptor = FetchDescriptor<TranscriptRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func delete(_ record: TranscriptRecord) throws {
        context.delete(record)
        try context.save()
    }

    public func clear() throws {
        let records = try fetchAll()
        for record in records {
            context.delete(record)
        }
        try context.save()
    }
}
