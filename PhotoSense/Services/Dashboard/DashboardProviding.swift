import Foundation

protocol DashboardProviding: Sendable {
    func makeSnapshot(isRefreshing: Bool) async throws -> DashboardSnapshot
    func makeSnapshot(from records: [MediaAssetIndexRecord], isRefreshing: Bool) async -> DashboardSnapshot
}
