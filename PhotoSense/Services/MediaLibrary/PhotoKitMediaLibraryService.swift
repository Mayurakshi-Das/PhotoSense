@preconcurrency import AVFoundation
@preconcurrency import CoreLocation
@preconcurrency import Photos
import Foundation

actor PhotoKitMediaLibraryService: MediaLibraryProviding {
    func authorizationStatus() async -> MediaLibraryAuthorizationStatus {
        Self.mapAuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> MediaLibraryAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: Self.mapAuthorizationStatus(status))
            }
        }
    }

    private var fileSizeCache: [String: Int64] = [:]

    func fetchAssets() async throws -> [MediaLibraryAsset] {
        let status = await authorizationStatus()
        guard status.canReadLibrary else {
            throw MediaLibraryError.accessUnavailable(status)
        }

        return try await Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let options = PHFetchOptions()
            options.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(PHAsset.creationDate), ascending: false)
            ]

            let fetchResult = PHAsset.fetchAssets(with: options)
            var assets: [MediaLibraryAsset] = []
            assets.reserveCapacity(fetchResult.count)

            fetchResult.enumerateObjects { asset, _, stop in
                if Task.isCancelled {
                    stop.pointee = true
                    return
                }

                assets.append(Self.makeAsset(from: asset))
            }

            try Task.checkCancellation()
            return assets
        }.value
    }

    func fetchFileSize(for assetId: String) async -> Int64? {
        if let cached = fileSizeCache[assetId] {
            return cached
        }

        let size = await Task.detached(priority: .utility) { () -> Int64? in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            guard let asset = fetchResult.firstObject else { return nil }

            let resources = PHAssetResource.assetResources(for: asset)
            let videoSizes = resources
                .filter { Self.isVideoResource($0.type) }
                .compactMap(Self.resourceFileSize)

            if let largestVideoSize = videoSizes.max(), largestVideoSize > 0 {
                return largestVideoSize
            }

            let allResourceSizes = resources.compactMap(Self.resourceFileSize)
            if let largestResourceSize = allResourceSizes.max(), largestResourceSize > 0 {
                return largestResourceSize
            }

            if asset.mediaType == .video {
                return await Self.fetchLocalAVAssetFileSize(for: asset)
            }

            return nil
        }.value

        if let size {
            fileSizeCache[assetId] = size
        }
        return size
    }

    func deleteAssets(withIdentifiers ids: [String]) async throws {
        // PHPhotoLibrary.performChanges automatically presents the system deletion sheet.
        // The completion block throws if the user denies or an error occurs.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    // User cancelled the system deletion sheet
                    continuation.resume(throwing: MediaLibraryError.deletionCancelled)
                }
            }
        }
    }

    func checkAssetsExist(withIdentifiers ids: [String]) async -> Set<String> {
        await Task.detached(priority: .utility) {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var existingIDs = Set<String>()
            fetchResult.enumerateObjects { asset, _, _ in
                existingIDs.insert(asset.localIdentifier)
            }
            return existingIDs
        }.value
    }


    private nonisolated static func mapAuthorizationStatus(_ status: PHAuthorizationStatus) -> MediaLibraryAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .limited:
            .limited
        @unknown default:
            .unknown
        }
    }

    private nonisolated static func makeAsset(from asset: PHAsset) -> MediaLibraryAsset {
        MediaLibraryAsset(
            id: asset.localIdentifier,
            kind: mapMediaType(asset.mediaType),
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            location: mapLocation(asset.location),
            source: mapSource(asset.sourceType),
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            resources: []
        )
    }

    private nonisolated static func makeResources(for asset: PHAsset) -> [MediaResourceDescriptor] {
        PHAssetResource.assetResources(for: asset).enumerated().map { index, resource in
            let fileSize = (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value
            return MediaResourceDescriptor(
                id: "\(asset.localIdentifier)#\(index)",
                kind: mapResourceType(resource.type),
                uniformTypeIdentifier: resource.uniformTypeIdentifier,
                originalFilename: originalFilename(for: resource),
                fileSize: fileSize
            )
        }
    }

    private nonisolated static func originalFilename(for resource: PHAssetResource) -> String? {
        if #available(iOS 27.0, *) {
            return resource.filename
        } else {
            return resource.originalFilename
        }
    }

    private nonisolated static func resourceFileSize(for resource: PHAssetResource) -> Int64? {
        guard let sizeNumber = resource.value(forKey: "fileSize") as? NSNumber else { return nil }
        let size = sizeNumber.int64Value
        return size > 0 ? size : nil
    }

    private nonisolated static func isVideoResource(_ type: PHAssetResourceType) -> Bool {
        switch type {
        case .video, .fullSizeVideo, .pairedVideo, .fullSizePairedVideo,
             .adjustmentBaseVideo, .adjustmentBasePairedVideo:
            return true
        default:
            return false
        }
    }

    private nonisolated static func fetchLocalAVAssetFileSize(for asset: PHAsset) async -> Int64? {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .fastFormat
        options.version = .current
        options.isNetworkAccessAllowed = false

        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { asset, _, _ in
                nonisolated(unsafe) let transferred = asset
                continuation.resume(returning: transferred)
            }
        }

        guard let urlAsset = avAsset as? AVURLAsset else { return nil }

        do {
            let values = try urlAsset.url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey])
            if let total = values.totalFileSize, total > 0 {
                return Int64(total)
            }
            if let fileSize = values.fileSize, fileSize > 0 {
                return Int64(fileSize)
            }
        } catch {
            return nil
        }

        return nil
    }

    private nonisolated static func mapMediaType(_ mediaType: PHAssetMediaType) -> MediaAssetKind {
        switch mediaType {
        case .image:
            .photo
        case .video:
            .video
        case .audio, .unknown:
            .unknown
        @unknown default:
            .unknown
        }
    }

    private nonisolated static func mapLocation(_ location: CLLocation?) -> MediaLocationCoordinate? {
        guard let location else {
            return nil
        }

        return MediaLocationCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    private nonisolated static func mapSource(_ sourceType: PHAssetSourceType) -> MediaAssetSource {
        if sourceType.contains(.typeUserLibrary) {
            return .userLibrary
        }

        if sourceType.contains(.typeCloudShared) {
            return .cloudShared
        }

        if sourceType.contains(.typeiTunesSynced) {
            return .iTunesSynced
        }

        return .unknown
    }

    private nonisolated static func mapResourceType(_ resourceType: PHAssetResourceType) -> MediaResourceKind {
        switch resourceType {
        case .photo:
            .photo
        case .video:
            .video
        case .audio:
            .audio
        case .pairedVideo:
            .pairedVideo
        case .fullSizePhoto:
            .fullSizePhoto
        case .fullSizeVideo:
            .fullSizeVideo
        case .adjustmentData:
            .adjustmentData
        case .adjustmentBasePhoto:
            .adjustmentBasePhoto
        case .adjustmentBaseVideo:
            .adjustmentBaseVideo
        case .adjustmentBasePairedVideo:
            .adjustmentBasePairedVideo
        case .alternatePhoto:
            .alternatePhoto
        case .fullSizePairedVideo:
            .fullSizePairedVideo
        case .photoProxy:
            .photoProxy
        @unknown default:
            .unknown
        }
    }
}
