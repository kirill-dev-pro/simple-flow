import Foundation
import SwiftData

public enum DatabaseContainerFactory {
    public static let shared: ModelContainer = {
        do {
            return try create(inMemory: false)
        } catch {
            fatalError("Failed to initialize persistent DatabaseContainer: \(error)")
        }
    }()

    public static func create(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([TranscriptRecord.self])

        if inMemory {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        }

        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = appSupportURL.appendingPathComponent("dev.kirill.simpleflow", isDirectory: true)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let storeURL = directoryURL.appendingPathComponent("SimpleFlow.store")
        let modelConfiguration = ModelConfiguration(
            "SimpleFlow",
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            AppLogger.lifecycle.error("Failed to open persistent store at \(storeURL.path, privacy: .public), attempting lock recovery: \(error.localizedDescription, privacy: .public)")

            let walURL = directoryURL.appendingPathComponent("SimpleFlow.store-wal")
            let shmURL = directoryURL.appendingPathComponent("SimpleFlow.store-shm")
            try? fileManager.removeItem(at: walURL)
            try? fileManager.removeItem(at: shmURL)

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                AppLogger.lifecycle.error("Persistent store re-open failed, resetting store file: \(error.localizedDescription, privacy: .public)")
                try? fileManager.removeItem(at: storeURL)
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            }
        }
    }
}
