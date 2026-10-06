import Foundation
import SwiftData

@Model
final class PersistentMediaAssetIndexRecord {
    @Attribute(.unique) var id: String
    var kindRawValue: String
    var creationDate: Date?
    var modificationDate: Date?
    var pixelWidth: Int
    var pixelHeight: Int
    var duration: TimeInterval
    var latitude: Double?
    var longitude: Double?
    var sourceRawValue: String
    var isFavorite: Bool
    var isHidden: Bool
    var isScreenshot: Bool
    var resourceTypeRawValues: [String]
    var uniformTypeIdentifiers: [String]
    var originalFilenames: [String]
    var indexedAt: Date
    var processingStateRawValue: String
    var fileSize: Int64?

    init(record: MediaAssetIndexRecord) {
        self.id = record.id
        self.kindRawValue = record.kind.rawValue
        self.creationDate = record.creationDate
        self.modificationDate = record.modificationDate
        self.pixelWidth = record.pixelWidth
        self.pixelHeight = record.pixelHeight
        self.duration = record.duration
        self.latitude = record.location?.latitude
        self.longitude = record.location?.longitude
        self.sourceRawValue = record.source.rawValue
        self.isFavorite = record.isFavorite
        self.isHidden = record.isHidden
        self.isScreenshot = record.isScreenshot
        self.resourceTypeRawValues = record.resourceTypes.map(\.rawValue).sorted()
        self.uniformTypeIdentifiers = record.uniformTypeIdentifiers.sorted()
        self.originalFilenames = record.originalFilenames.sorted()
        self.indexedAt = record.indexedAt
        self.processingStateRawValue = record.processingState.rawValue
        self.fileSize = record.fileSize
    }

    var indexRecord: MediaAssetIndexRecord {
        MediaAssetIndexRecord(
            id: id,
            kind: MediaAssetKind(rawValue: kindRawValue) ?? .unknown,
            creationDate: creationDate,
            modificationDate: modificationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            duration: duration,
            location: makeLocation(),
            source: MediaAssetSource(rawValue: sourceRawValue) ?? .unknown,
            isFavorite: isFavorite,
            isHidden: isHidden,
            isScreenshot: isScreenshot,
            resourceTypes: Set(resourceTypeRawValues.map { MediaResourceKind(rawValue: $0) ?? .unknown }),
            uniformTypeIdentifiers: Set(uniformTypeIdentifiers),
            originalFilenames: Set(originalFilenames),
            indexedAt: indexedAt,
            processingState: MediaAssetProcessingState(rawValue: processingStateRawValue) ?? .failed,
            fileSize: fileSize
        )
    }

    private func makeLocation() -> MediaLocationCoordinate? {
        guard let latitude, let longitude else {
            return nil
        }

        return MediaLocationCoordinate(latitude: latitude, longitude: longitude)
    }
}
