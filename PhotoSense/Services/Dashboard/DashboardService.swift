import Foundation

actor DashboardService: DashboardProviding {
    private let indexStore: any MediaIndexStoring
    private let binService: BinService

    init(
        indexStore: any MediaIndexStoring,
        binService: BinService = .shared
    ) {
        self.indexStore = indexStore
        self.binService = binService
    }

    func makeSnapshot(isRefreshing: Bool = false) async throws -> DashboardSnapshot {
        let records = try await indexStore.loadRecords()
        return await makeSnapshot(from: records, isRefreshing: isRefreshing)
    }

    func makeSnapshot(from records: [MediaAssetIndexRecord], isRefreshing: Bool) async -> DashboardSnapshot {
        let summary = MediaIndexSummary(records: records, failures: [])
        let latestIndexDate = records.map(\.indexedAt).max()
        let binCount = await binService.activeItemCount()

        let sessionState = await DuplicatePhotosSessionService.shared.state
        let dupState: DashboardCategoryState
        switch sessionState {
        case .notAnalyzed:
            dupState = .notAnalyzed
        case .analyzing:
            dupState = .loading
        case .ready(let result):
            dupState = result.groups.isEmpty ? .empty : .available(count: result.groups.count)
        case .empty:
            dupState = .empty
        case .failed(let message):
            dupState = .failed(message)
        }

        let videoSessionState = await DuplicateVideosSessionService.shared.state
        let dupVideoState: DashboardCategoryState
        switch videoSessionState {
        case .notAnalyzed:
            dupVideoState = .notAnalyzed
        case .analyzing:
            dupVideoState = .loading
        case .ready(let result):
            dupVideoState = result.groups.isEmpty ? .empty : .available(count: result.groups.count)
        case .empty:
            dupVideoState = .empty
        case .failed(let message):
            dupVideoState = .failed(message)
        }

        let similarSessionState = await SimilarPhotosSessionService.shared.state
        let similarState: DashboardCategoryState
        switch similarSessionState {
        case .notAnalyzed:
            similarState = .notAnalyzed
        case .analyzing:
            similarState = .loading
        case .ready(let result):
            similarState = result.groups.isEmpty ? .empty : .available(count: result.groups.count)
        case .empty:
            similarState = .empty
        case .failed(let message):
            similarState = .failed(message)
        }

        return DashboardSnapshot(
            categories: [
                DashboardCategorySummary(
                    category: .screenshots,
                    state: countState(summary.screenshots)
                ),
                DashboardCategorySummary(
                    category: .videos,
                    state: countState(summary.videos)
                ),
                DashboardCategorySummary(
                    category: .duplicatePhotos,
                    state: dupState
                ),
                DashboardCategorySummary(
                    category: .duplicateVideos,
                    state: dupVideoState
                ),
                DashboardCategorySummary(
                    category: .similarPhotos,
                    state: similarState
                ),
                DashboardCategorySummary(
                    category: .largeVideos,
                    state: countState(summary.videos)
                ),
                DashboardCategorySummary(
                    category: .bin,
                    state: binCount > 0 ? .available(count: binCount) : .empty
                )
            ],
            indexSummary: summary,
            records: records,
            lastIndexedAt: latestIndexDate,
            isRefreshing: isRefreshing
        )
    }

    private func countState(_ count: Int) -> DashboardCategoryState {
        count > 0 ? .available(count: count) : .empty
    }
}

