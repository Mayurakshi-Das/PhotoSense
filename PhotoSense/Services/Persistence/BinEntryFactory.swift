import Foundation
import UIKit

enum BinEntryFactory {
    static func make(
        assetId: String,
        kind: BinAssetKind,
        fileSize: Int64
    ) async -> BinEntry {
        let image = await ThumbnailPipeline.shared.thumbnail(
            for: assetId,
            targetSize: CGSize(width: 240, height: 240)
        )
        let thumbnailData = image?.jpegData(compressionQuality: 0.72)

        return BinEntry(
            assetId: assetId,
            kind: kind,
            fileSize: fileSize,
            thumbnailData: thumbnailData
        )
    }

    static func make(for record: MediaAssetIndexRecord) async -> BinEntry {
        await make(
            assetId: record.id,
            kind: record.binAssetKind,
            fileSize: record.fileSize ?? 0
        )
    }
}
