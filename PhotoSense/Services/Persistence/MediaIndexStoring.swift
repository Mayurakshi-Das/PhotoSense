import Foundation

protocol MediaIndexStoring: Sendable {
    func loadRecords() async throws -> [MediaAssetIndexRecord]
    func replaceIndex(with snapshot: MediaIndexSnapshot) async throws
}
