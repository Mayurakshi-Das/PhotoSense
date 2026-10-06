import Foundation

/// A lightweight value type representing a pending Bin entry, used by callers before it is persisted.
struct BinEntry: Sendable {
    let assetId: String
    let kind: BinAssetKind
    let fileSize: Int64
    let thumbnailData: Data?

    init(
        assetId: String,
        kind: BinAssetKind,
        fileSize: Int64,
        thumbnailData: Data? = nil
    ) {
        self.assetId = assetId
        self.kind = kind
        self.fileSize = fileSize
        self.thumbnailData = thumbnailData
    }
}
