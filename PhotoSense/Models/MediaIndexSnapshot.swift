import Foundation

struct MediaIndexSnapshot: Equatable, Sendable {
    let authorizationStatus: MediaLibraryAuthorizationStatus
    let records: [MediaAssetIndexRecord]
    let failures: [MediaIndexingFailure]
    let createdAt: Date

    var summary: MediaIndexSummary {
        MediaIndexSummary(records: records, failures: failures)
    }
}

struct MediaIndexingFailure: Identifiable, Equatable, Sendable {
    let id: String
    let reason: String
}

struct MediaIndexSummary: Equatable, Sendable {
    let totalAssets: Int
    let photos: Int
    let videos: Int
    let screenshots: Int
    let failures: Int

    static let empty = MediaIndexSummary()

    init(
        totalAssets: Int = 0,
        photos: Int = 0,
        videos: Int = 0,
        screenshots: Int = 0,
        failures: Int = 0
    ) {
        self.totalAssets = totalAssets
        self.photos = photos
        self.videos = videos
        self.screenshots = screenshots
        self.failures = failures
    }

    init(records: [MediaAssetIndexRecord], failures: [MediaIndexingFailure]) {
        self.totalAssets = records.count
        self.photos = records.filter { $0.kind == .photo }.count
        self.videos = records.filter { $0.kind == .video }.count
        self.screenshots = records.filter(\.isScreenshot).count
        self.failures = failures.count
    }
}
