import Foundation
import SwiftData

/// Actor-isolated service that manages the Bin — tracking deleted assets for 30-day recovery.
/// Uses its own SwiftData container so Bin records are independent of the main media index store.
actor BinService {
    static let shared = BinService()

    private let container: ModelContainer

    init() {
        let schema = Schema([BinRecord.self])
        let config = ModelConfiguration("BinStore", schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            let storeURL = URL.applicationSupportDirectory.appending(path: "BinStore.store")
            try? FileManager.default.removeItem(at: storeURL)
            if let retryContainer = try? ModelContainer(for: schema, configurations: [config]) {
                container = retryContainer
                return
            }
            let memConfig = ModelConfiguration("BinStore", schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [memConfig])
        }
    }

    // MARK: - Adding items

    /// Add new entries to the Bin. Skips assets already in the Bin to avoid duplicates.
    func addItems(_ entries: [BinEntry]) async {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        for entry in entries {
            // Check for existing record to avoid duplicates
            let id = entry.assetId
            let descriptor = FetchDescriptor<BinRecord>(
                predicate: #Predicate { $0.assetId == id }
            )
            if (try? context.fetch(descriptor))?.isEmpty == false { continue }

            let record = BinRecord(
                assetId: entry.assetId,
                kind: entry.kind,
                fileSize: entry.fileSize,
                thumbnailData: entry.thumbnailData
            )
            context.insert(record)
        }

        try? context.save()
    }

    // MARK: - Fetching

    /// Returns all current Bin items (active, not yet expired) as Sendable value types.
    func fetchActiveItems() async throws -> [BinItem] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let descriptor = FetchDescriptor<BinRecord>(
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        return all.compactMap { record in
            record.isExpired ? nil : record.toItem()
        }
    }

    /// Returns the count of active (non-expired) Bin items.
    func activeItemCount() async -> Int {
        (try? await fetchActiveItems())?.count ?? 0
    }

    /// Returns total reclaimable space in the Bin (sum of active record sizes).
    func totalReclaimableBytes() async -> Int64 {
        ((try? await fetchActiveItems()) ?? []).reduce(Int64(0)) { $0 + $1.fileSize }
    }

    // MARK: - Restoration

    /// Marks an item as restored by removing it from the Bin (the original asset still exists in Photos — it was never deleted).
    /// NOTE: We record items in the bin before the user confirms deletion in the Photos sheet.
    /// If the user cancelled the system sheet, we call this to clean up optimistic Bin entries.
    func removeItems(withIDs ids: Set<String>) async {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        for id in ids {
            let descriptor = FetchDescriptor<BinRecord>(
                predicate: #Predicate { $0.assetId == id }
            )
            if let records = try? context.fetch(descriptor) {
                records.forEach { context.delete($0) }
            }
        }

        try? context.save()
    }

    // MARK: - Expiry cleanup

    /// Deletes all expired Bin records (older than 30 days). Should be called on app launch.
    func purgeExpiredItems() async {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let descriptor = FetchDescriptor<BinRecord>()
        guard let all = try? context.fetch(descriptor) else { return }

        for record in all where record.isExpired {
            context.delete(record)
        }

        try? context.save()
    }
}
