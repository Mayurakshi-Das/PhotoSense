import Foundation
import SwiftData

/// The kind of media asset in the Bin.
enum BinAssetKind: String, Codable, Sendable {
    case photo
    case video
    case unknown
}

/// A SwiftData-persisted record representing an asset that has been moved to the Bin.
/// Items are considered permanently deleted after `retentionDays` days.
@Model
final class BinRecord {
    static let retentionDays: Int = 30

    @Attribute(.unique) var assetId: String
    var kindRawValue: String
    var fileSize: Int64
    var deletedAt: Date
    @Attribute(.externalStorage) var thumbnailData: Data?

    init(
        assetId: String,
        kind: BinAssetKind,
        fileSize: Int64,
        deletedAt: Date = .now,
        thumbnailData: Data? = nil
    ) {
        self.assetId = assetId
        self.kindRawValue = kind.rawValue
        self.fileSize = fileSize
        self.deletedAt = deletedAt
        self.thumbnailData = thumbnailData
    }

    var kind: BinAssetKind {
        BinAssetKind(rawValue: kindRawValue) ?? .unknown
    }

    /// Days remaining before permanent deletion (0 when expired).
    var daysRemaining: Int {
        let calendar = Calendar.current
        let expiryDate = calendar.date(byAdding: .day, value: BinRecord.retentionDays, to: deletedAt) ?? deletedAt
        let days = calendar.dateComponents([.day], from: .now, to: expiryDate).day ?? 0
        return max(0, days)
    }

    var isExpired: Bool { daysRemaining == 0 }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    func toItem() -> BinItem {
        BinItem(
            assetId: assetId,
            kind: kind,
            fileSize: fileSize,
            deletedAt: deletedAt,
            thumbnailData: thumbnailData
        )
    }
}

/// A Sendable, thread-safe value representation of an item in the Bin.
struct BinItem: Identifiable, Sendable {
    var id: String { assetId }
    let assetId: String
    let kind: BinAssetKind
    let fileSize: Int64
    let deletedAt: Date
    let thumbnailData: Data?

    init(
        assetId: String,
        kind: BinAssetKind,
        fileSize: Int64,
        deletedAt: Date,
        thumbnailData: Data? = nil
    ) {
        self.assetId = assetId
        self.kind = kind
        self.fileSize = fileSize
        self.deletedAt = deletedAt
        self.thumbnailData = thumbnailData
    }

    /// Days remaining before permanent deletion (0 when expired).
    var daysRemaining: Int {
        let calendar = Calendar.current
        let expiryDate = calendar.date(byAdding: .day, value: BinRecord.retentionDays, to: deletedAt) ?? deletedAt
        let days = calendar.dateComponents([.day], from: .now, to: expiryDate).day ?? 0
        return max(0, days)
    }

    var isExpired: Bool { daysRemaining == 0 }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
