import Foundation

enum DashboardCategoryState: Equatable, Sendable {
    case loading
    case available(count: Int)
    case empty
    case notAnalyzed
    case failed(String)

    var displayText: String {
        switch self {
        case .loading:
            "Loading"
        case .available(let count):
            count.formatted()
        case .empty:
            "Empty"
        case .notAnalyzed:
            "Pending"
        case .failed:
            "Issue"
        }
    }

    var detailText: String {
        switch self {
        case .loading:
            "Indexing..."
        case .available(let count):
            count == 1 ? "1 item" : "\(count.formatted()) items"
        case .empty:
            "No indexed items"
        case .notAnalyzed:
            "Not analyzed yet"
        case .failed(let message):
            message
        }
    }
}

struct DashboardCategorySummary: Identifiable, Equatable, Sendable {
    let category: DashboardCategory
    let state: DashboardCategoryState

    var id: DashboardCategory.ID { category.id }
}

struct DashboardSnapshot: Equatable, Sendable {
    let categories: [DashboardCategorySummary]
    let indexSummary: MediaIndexSummary
    let records: [MediaAssetIndexRecord]
    let lastIndexedAt: Date?
    let isRefreshing: Bool

    init(
        categories: [DashboardCategorySummary],
        indexSummary: MediaIndexSummary,
        records: [MediaAssetIndexRecord] = [],
        lastIndexedAt: Date?,
        isRefreshing: Bool
    ) {
        self.categories = categories
        self.indexSummary = indexSummary
        self.records = records
        self.lastIndexedAt = lastIndexedAt
        self.isRefreshing = isRefreshing
    }

    static let empty = DashboardSnapshot(
        categories: DashboardCategory.allCases.map {
            DashboardCategorySummary(category: $0, state: .loading)
        },
        indexSummary: .empty,
        records: [],
        lastIndexedAt: nil,
        isRefreshing: false
    )
}
