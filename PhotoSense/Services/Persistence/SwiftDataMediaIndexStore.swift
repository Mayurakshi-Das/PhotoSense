import Foundation
import SwiftData

actor SwiftDataMediaIndexStore: MediaIndexStoring {
    private let container: ModelContainer

    init(inMemory: Bool = false) throws {
        let schema = Schema([
            PersistentMediaAssetIndexRecord.self
        ])
        let configuration = ModelConfiguration(
            "MediaIndexStore",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        var resolvedContainer: ModelContainer?

        do {
            resolvedContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            if !inMemory {
                // Attempt to recover by deleting the corrupt on-disk store
                let storeURL = URL.applicationSupportDirectory
                    .appending(path: "MediaIndexStore.store")
                try? FileManager.default.removeItem(at: storeURL)
                // Use a fresh config name to avoid reuse-after-failure assertion
                let recoveryConfig = ModelConfiguration(
                    "MediaIndexStore-Recovery",
                    schema: schema,
                    isStoredInMemoryOnly: false
                )
                if let recovered = try? ModelContainer(
                    for: schema,
                    configurations: [recoveryConfig]
                ) {
                    resolvedContainer = recovered
                }
            }

            if resolvedContainer == nil {
                // Last resort: fall back to in-memory so the app can still run
                let memConfig = ModelConfiguration(
                    "MediaIndexStore-Memory",
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                resolvedContainer = try ModelContainer(
                    for: schema,
                    configurations: [memConfig]
                )
            }
        }

        // resolvedContainer is guaranteed non-nil here (throws if all paths fail)
        self.container = resolvedContainer!
    }

    func loadRecords() async throws -> [MediaAssetIndexRecord] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let descriptor = FetchDescriptor<PersistentMediaAssetIndexRecord>(
            sortBy: [SortDescriptor(\.indexedAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)

        return records.map(\.indexRecord)
    }

    func replaceIndex(with snapshot: MediaIndexSnapshot) async throws {
        try Task.checkCancellation()

        let context = ModelContext(container)
        context.autosaveEnabled = false

        let existing = try context.fetch(FetchDescriptor<PersistentMediaAssetIndexRecord>())
        for record in existing {
            context.delete(record)
        }

        for record in snapshot.records {
            try Task.checkCancellation()
            context.insert(PersistentMediaAssetIndexRecord(record: record))
        }

        try context.save()
    }
}
