import Foundation

actor UnavailableMediaIndexStore: MediaIndexStoring {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func loadRecords() async throws -> [MediaAssetIndexRecord] {
        throw MediaIndexStoreError.unavailable(reason)
    }

    func replaceIndex(with snapshot: MediaIndexSnapshot) async throws {
        throw MediaIndexStoreError.unavailable(reason)
    }
}
