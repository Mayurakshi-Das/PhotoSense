import Foundation

enum MediaAssetProcessingState: String, Codable, Hashable, Sendable {
    case metadataIndexed
    case unavailable
    case failed
}

struct MediaAssetIndexRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: MediaAssetKind
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let location: MediaLocationCoordinate?
    let source: MediaAssetSource
    let isFavorite: Bool
    let isHidden: Bool
    let isScreenshot: Bool
    let resourceTypes: Set<MediaResourceKind>
    let uniformTypeIdentifiers: Set<String>
    let originalFilenames: Set<String>
    let indexedAt: Date
    let processingState: MediaAssetProcessingState
    let fileSize: Int64?

    init(
        id: String,
        kind: MediaAssetKind,
        creationDate: Date?,
        modificationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: TimeInterval,
        location: MediaLocationCoordinate?,
        source: MediaAssetSource,
        isFavorite: Bool,
        isHidden: Bool,
        isScreenshot: Bool,
        resourceTypes: Set<MediaResourceKind>,
        uniformTypeIdentifiers: Set<String>,
        originalFilenames: Set<String>,
        indexedAt: Date,
        processingState: MediaAssetProcessingState,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.location = location
        self.source = source
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.isScreenshot = isScreenshot
        self.resourceTypes = resourceTypes
        self.uniformTypeIdentifiers = uniformTypeIdentifiers
        self.originalFilenames = originalFilenames
        self.indexedAt = indexedAt
        self.processingState = processingState
        self.fileSize = fileSize
    }

    init(asset: MediaLibraryAsset, indexedAt: Date = .now) {
        self.id = asset.id
        self.kind = asset.kind
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.duration = asset.duration
        self.location = asset.location
        self.source = asset.source
        self.isFavorite = asset.isFavorite
        self.isHidden = asset.isHidden
        self.isScreenshot = asset.isScreenshot
        self.resourceTypes = Set(asset.resources.map(\.kind))
        self.uniformTypeIdentifiers = Set(asset.resources.compactMap(\.uniformTypeIdentifier))
        self.originalFilenames = Set(asset.resources.compactMap(\.originalFilename))
        self.indexedAt = indexedAt
        self.processingState = .metadataIndexed
        self.fileSize = asset.resources.compactMap(\.fileSize).max()
    }
}

extension MediaAssetIndexRecord {
    var formattedDuration: String {
        guard duration > 0 else { return "00:00" }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var formattedFileSize: String? {
        guard let fileSize, fileSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var resolutionString: String {
        guard pixelWidth > 0 && pixelHeight > 0 else { return "" }
        if (pixelWidth >= 3840 && pixelHeight >= 2160) || (pixelWidth >= 2160 && pixelHeight >= 3840) {
            return "4K"
        } else if (pixelWidth >= 1920 && pixelHeight >= 1080) || (pixelWidth >= 1080 && pixelHeight >= 1920) {
            return "1080p"
        } else if (pixelWidth >= 1280 && pixelHeight >= 720) || (pixelWidth >= 720 && pixelHeight >= 1280) {
            return "720p"
        } else {
            return "\(pixelWidth) × \(pixelHeight)"
        }
    }

    var binAssetKind: BinAssetKind {
        kind == .video ? .video : .photo
    }

    func withFileSize(_ newSize: Int64?) -> MediaAssetIndexRecord {
        MediaAssetIndexRecord(
            id: id,
            kind: kind,
            creationDate: creationDate,
            modificationDate: modificationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            duration: duration,
            location: location,
            source: source,
            isFavorite: isFavorite,
            isHidden: isHidden,
            isScreenshot: isScreenshot,
            resourceTypes: resourceTypes,
            uniformTypeIdentifiers: uniformTypeIdentifiers,
            originalFilenames: originalFilenames,
            indexedAt: indexedAt,
            processingState: processingState,
            fileSize: newSize
        )
    }
}

