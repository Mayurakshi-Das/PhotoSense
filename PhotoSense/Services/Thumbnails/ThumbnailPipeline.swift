import Foundation
import Photos
import UIKit

protocol ThumbnailPipelineProviding: Sendable {
    func thumbnail(for assetId: String, targetSize: CGSize) async -> UIImage?
}

actor ThumbnailPipeline: ThumbnailPipelineProviding {
    static let shared = ThumbnailPipeline()

    private let imageManager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init(countLimit: Int = 400, totalCostLimitMB: Int = 80) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimitMB * 1024 * 1024
    }

    func thumbnail(for assetId: String, targetSize: CGSize) async -> UIImage? {
        let cacheKey = "\(assetId)_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let keyString = cacheKey as String
        if let existing = inFlightTasks[keyString] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            await self.loadThumbnailFromPhotoKit(assetId: assetId, targetSize: targetSize)
        }

        inFlightTasks[keyString] = task
        let image = await task.value
        inFlightTasks.removeValue(forKey: keyString)

        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: cacheKey, cost: cost)
        }

        return image
    }

    private func loadThumbnailFromPhotoKit(assetId: String, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            guard let asset = fetchResult.firstObject else {
                continuation.resume(returning: nil)
                return
            }

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            options.isSynchronous = false

            var hasResumed = false
            self.imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func clearMemoryCache() {
        cache.removeAllObjects()
    }
}
