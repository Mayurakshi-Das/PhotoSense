import Foundation

actor MediaIndexingService: MediaIndexing {
    private let mediaLibrary: any MediaLibraryProviding
    private let indexStore: (any MediaIndexStoring)?

    init(
        mediaLibrary: any MediaLibraryProviding,
        indexStore: (any MediaIndexStoring)? = nil
    ) {
        self.mediaLibrary = mediaLibrary
        self.indexStore = indexStore
    }

    func buildIndex() async throws -> MediaIndexSnapshot {
        let status = await mediaLibrary.authorizationStatus()
        guard status.canReadLibrary else {
            throw MediaIndexingError.authorizationRequired(status)
        }

        let indexedAt = Date()
        let assets = try await mediaLibrary.fetchAssets()

        // Indexing is metadata-only in this phase. Heavy hashes, Vision requests, and video
        // resource reads stay out of this path so dashboard startup remains responsive.
        let records = assets.map { MediaAssetIndexRecord(asset: $0, indexedAt: indexedAt) }

        let snapshot = MediaIndexSnapshot(
            authorizationStatus: status,
            records: records,
            failures: [],
            createdAt: indexedAt
        )

        Task.detached(priority: .utility) { [indexStore = self.indexStore] in
            try? await indexStore?.replaceIndex(with: snapshot)
        }

        return snapshot
    }
}
