import AppKit
import SwiftData
import SwiftUI

public struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptRecord.createdAt, order: .reverse) private var records: [TranscriptRecord]
    @State private var selectedRecordId: UUID?
    @State private var showingClearConfirmation = false

    public init() {}

    private var selectedRecord: TranscriptRecord? {
        guard let selectedRecordId else { return nil }
        return records.first { $0.id == selectedRecordId }
    }

    public var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Transcripts",
                    systemImage: "text.bubble",
                    description: Text("Transcriptions will appear here after dictation.")
                )
            } else {
                NavigationSplitView {
                    List(selection: $selectedRecordId) {
                        ForEach(records) { record in
                            HistoryRowView(
                                record: record,
                                onCopy: { copyToClipboard(record.text) },
                                onDelete: { deleteRecord(record) }
                            )
                            .tag(record.id)
                            .contextMenu {
                                Button {
                                    copyToClipboard(record.text)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    deleteRecord(record)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteRecord(record)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
                } detail: {
                    if let selectedRecord {
                        HistoryDetailView(
                            record: selectedRecord,
                            onCopy: { copyToClipboard(selectedRecord.text) },
                            onDelete: { deleteRecord(selectedRecord) }
                        )
                    } else {
                        ContentUnavailableView(
                            "Select a Transcript",
                            systemImage: "doc.text",
                            description: Text("Choose a transcript from the list to view its full content.")
                        )
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(records.isEmpty)
                .help("Clear all transcript history")
            }
        }
        .confirmationDialog(
            "Are you sure you want to clear all transcript history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func deleteRecord(_ record: TranscriptRecord) {
        if selectedRecordId == record.id {
            selectedRecordId = nil
        }
        modelContext.delete(record)
        try? modelContext.save()
    }

    private func clearHistory() {
        selectedRecordId = nil
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
    }
}

private struct HistoryRowView: View {
    let record: TranscriptRecord
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(record.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                StatusBadge(status: record.insertionStatus)

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy transcript")
            }

            Text(record.text)
                .lineLimit(2)
                .font(.body)

            if let sourceApp = record.sourceApplicationName, !sourceApp.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "app.dashed")
                        .font(.caption2)
                    Text(sourceApp)
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HistoryDetailView: View {
    let record: TranscriptRecord
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.createdAt.formatted(date: .complete, time: .standard))
                        .font(.headline)
                    if let sourceApp = record.sourceApplicationName, !sourceApp.isEmpty {
                        Text("Target: \(sourceApp)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                StatusBadge(status: record.insertionStatus)

                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }

            Divider()

            ScrollView {
                Text(record.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct StatusBadge: View {
    let status: InsertionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusTitle)
                .font(.caption2)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusTitle: String {
        switch status {
        case .inserted:
            return "Inserted"
        case .focusChanged:
            return "Focus Changed"
        case .pasteFailed:
            return "Paste Failed"
        }
    }

    private var statusColor: Color {
        switch status {
        case .inserted:
            return .green
        case .focusChanged:
            return .orange
        case .pasteFailed:
            return .red
        }
    }
}
