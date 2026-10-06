@preconcurrency import Vision
import Foundation
import Photos
import UIKit

// MARK: - Result types

/// One group of photos that are duplicates of each other.
struct DuplicatePhotoGroup: Identifiable, Sendable, Hashable {
    let id: String            // stable ID derived from the representative asset
    let photos: [MediaAssetIndexRecord]

    /// The "best" representative to show as the group thumbnail (largest file size).
    var representative: MediaAssetIndexRecord { photos[0] }

    /// Suggested candidates for deletion (all except the representative).
    var deletionCandidates: [MediaAssetIndexRecord] { Array(photos.dropFirst()) }

    var totalStorageBytes: Int64 {
        photos.compactMap(\.fileSize).reduce(0, +)
    }

    var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
    }
}

struct DuplicatePhotoAnalysisResult: Sendable {
    let groups: [DuplicatePhotoGroup]
    let analyzedPhotoCount: Int

    var duplicateGroupCount: Int { groups.count }

    /// Total number of extra copies that could be deleted.
    var deletableCopyCount: Int { groups.reduce(0) { $0 + $1.deletionCandidates.count } }

    var totalReclaimableBytes: Int64 {
        groups.flatMap(\.deletionCandidates).compactMap(\.fileSize).reduce(0, +)
    }

    var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalReclaimableBytes, countStyle: .file)
    }

    /// Returns a new result with the specified asset IDs removed from all groups,
    /// pruning groups that have fewer than 2 remaining photos.
    func removing(ids: Set<String>) -> DuplicatePhotoAnalysisResult {
        let updatedGroups = groups.compactMap { group -> DuplicatePhotoGroup? in
            let remaining = group.photos.filter { !ids.contains($0.id) }
            guard remaining.count >= 2 else { return nil }
            return DuplicatePhotoGroup(id: group.id, photos: remaining)
        }
        return DuplicatePhotoAnalysisResult(
            groups: updatedGroups,
            analyzedPhotoCount: analyzedPhotoCount
        )
    }
}

// MARK: - Protocol

// MARK: - Match Classification (Preserves Similar Photos detection)

/// Classification of photo content relationship.
/// Strictly separates content-identical duplicates from visually-similar photos.
enum PhotoMatchClassification: Sendable {
    case duplicate
    case similar
    case distinct

    /// Duplicate threshold: identical or re-encoded copy of the same image.
    static let maxDuplicateVisionDistance: Float = 0.05
    static let maxDuplicateDHashDistance: Int = 4

    /// Similar threshold (preserved for upcoming Similar Photos feature).
    static let maxSimilarVisionDistance: Float = 0.22
    static let maxSimilarDHashDistance: Int = 16

    static func classify(visionDistance: Float, dHashDistance: Int) -> PhotoMatchClassification {
        if visionDistance <= maxDuplicateVisionDistance && dHashDistance <= maxDuplicateDHashDistance {
            return .duplicate
        } else if visionDistance <= maxSimilarVisionDistance && dHashDistance <= maxSimilarDHashDistance {
            return .similar
        } else {
            return .distinct
        }
    }
}

// MARK: - Protocol

protocol DuplicatePhotoAnalyzing: Sendable {
    func analyzePhotos(
        from records: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding
    ) async throws -> DuplicatePhotoAnalysisResult
}

// MARK: - Engine

///** Multi-stage duplicate photo detection.**

/// **Stage 1 — Aspect Ratio & Metadata Candidate Bucketing**

/// **Stage 2 — High-Speed Perceptual Difference Hashing (dHash)**

/// **Stage 3 — Vision Feature Print Verification**

actor DuplicatePhotoAnalysisEngine: DuplicatePhotoAnalyzing {

    /// Thumbnail size fed to Vision and dHash — small for speed, accurate for feature extraction.
    private let featurePrintSize = CGSize(width: 192, height: 192)

    /// Maximum concurrent thumbnail fetches per batch.
    private let concurrencyLimit = 10

    private let analysisCache: MediaAnalysisCacheStore

    init(analysisCache: MediaAnalysisCacheStore = .shared) {
        self.analysisCache = analysisCache
    }

    func analyzePhotos(
        from records: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding
    ) async throws -> DuplicatePhotoAnalysisResult {
        try Task.checkCancellation()

        let photoRecords = records.filter { $0.kind == .photo }
        guard photoRecords.count >= 2 else {
            return DuplicatePhotoAnalysisResult(groups: [], analyzedPhotoCount: photoRecords.count)
        }

        // ── Stage 1: Metadata candidate grouping ────────────────────────────────
        let candidateBuckets = buildCandidateBuckets(from: photoRecords)
        guard !candidateBuckets.isEmpty else {
            return DuplicatePhotoAnalysisResult(groups: [], analyzedPhotoCount: photoRecords.count)
        }

        try Task.checkCancellation()

        // ── Stage 2 & 3: Content verification on candidate buckets ───────────────
        var groups: [DuplicatePhotoGroup] = []

        for bucket in candidateBuckets {
            try Task.checkCancellation()
            let bucketGroups = try await verifyDuplicates(in: bucket, mediaLibrary: mediaLibrary)
            groups.append(contentsOf: bucketGroups)
        }

        // Sort groups: largest storage impact first
        groups.sort { $0.totalStorageBytes > $1.totalStorageBytes }

        return DuplicatePhotoAnalysisResult(
            groups: groups,
            analyzedPhotoCount: photoRecords.count
        )
    }

    // MARK: - Stage 1: Metadata Bucketing

    private func buildCandidateBuckets(from records: [MediaAssetIndexRecord]) -> [[MediaAssetIndexRecord]] {
        struct BucketKey: Hashable {
            // Normalized aspect ratio rounded to 2 decimal places (orientation-independent)
            let aspectRatioTier: Int
            // Pixel size magnitude (e.g. 12MP, 24MP, 48MP) with 10% tolerance band
            let resolutionTier: Int
        }

        var buckets: [BucketKey: [MediaAssetIndexRecord]] = [:]

        for record in records {
            let w = max(1, record.pixelWidth)
            let h = max(1, record.pixelHeight)
            let maxDim = max(w, h)
            let minDim = min(w, h)

            // Aspect ratio tier (e.g. 4:3 is ~1.33 -> 133, 16:9 is ~1.78 -> 178)
            let ratio = Double(maxDim) / Double(minDim)
            let aspectRatioTier = Int(round(ratio * 100))

            // Megapixel tier
            let megaPixels = (Double(w) * Double(h)) / 1_000_000.0
            let resolutionTier = Int(round(megaPixels * 2))

            let key = BucketKey(aspectRatioTier: aspectRatioTier, resolutionTier: resolutionTier)
            buckets[key, default: []].append(record)
        }

        return buckets.values
            .filter { $0.count >= 2 }
            .map { $0 }
    }

    // MARK: - Stage 2 & 3: Verification (dHash + Vision)

    private struct PhotoFingerprint {
        let record: MediaAssetIndexRecord
        let dHash: UInt64
        let fp: VNFeaturePrintObservation
    }

    private func verifyDuplicates(
        in bucket: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding
    ) async throws -> [DuplicatePhotoGroup] {
        guard bucket.count >= 2 else { return [] }

        var fingerprints: [PhotoFingerprint] = []
        fingerprints.reserveCapacity(bucket.count)
        var uncachedRecords: [MediaAssetIndexRecord] = []

        for record in bucket {
            if let cached = await analysisCache.cachedDuplicatePhotoFingerprintData(for: record),
               let featurePrint = MediaAnalysisCacheStore.unarchiveFeaturePrint(from: cached.featurePrintData) {
                fingerprints.append(
                    PhotoFingerprint(
                        record: record,
                        dHash: cached.dHash,
                        fp: featurePrint
                    )
                )
            } else {
                uncachedRecords.append(record)
            }
        }

        for chunkStart in stride(from: 0, to: uncachedRecords.count, by: concurrencyLimit) {
            try Task.checkCancellation()
            let chunkEnd = min(chunkStart + concurrencyLimit, uncachedRecords.count)
            let chunk = Array(uncachedRecords[chunkStart..<chunkEnd])

            // Fetch thumbnails as fast JPEG data
            let chunkImages: [(MediaAssetIndexRecord, UIImage)] = await withTaskGroup(
                of: (MediaAssetIndexRecord, UIImage)?.self
            ) { group in
                for record in chunk {
                    let assetId = record.id
                    let targetSize = self.featurePrintSize
                    group.addTask {
                        guard let img = await ThumbnailPipeline.shared.thumbnail(for: assetId, targetSize: targetSize) else {
                            return nil
                        }
                        return (record, img)
                    }
                }
                var results: [(MediaAssetIndexRecord, UIImage)] = []
                for await result in group {
                    if let r = result { results.append(r) }
                }
                return results
            }

            // Generate dHash and Vision prints synchronously on actor
            var cacheUpdates: [(record: MediaAssetIndexRecord, dHash: UInt64, featurePrint: VNFeaturePrintObservation)] = []

            for (record, image) in chunkImages {
                guard let cgImage = image.cgImage else { continue }
                guard let dHash = Self.computeDHash(from: cgImage) else { continue }

                let request = VNGenerateImageFeaturePrintRequest()
                request.imageCropAndScaleOption = .scaleFill
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                    if let observation = request.results?.first as? VNFeaturePrintObservation {
                        fingerprints.append(PhotoFingerprint(record: record, dHash: dHash, fp: observation))
                        cacheUpdates.append((record: record, dHash: dHash, featurePrint: observation))
                    }
                } catch {
                    // Skip if Vision fails
                }
            }

            await analysisCache.storeDuplicatePhotoFingerprints(cacheUpdates)
            await Task.yield()
        }

        guard fingerprints.count >= 2 else { return [] }

        // Step B: Pairwise comparison with strict duplicate verification
        var parent = Array(0..<fingerprints.count)

        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }

        for i in 0..<fingerprints.count {
            for j in (i + 1)..<fingerprints.count {
                let fpA = fingerprints[i]
                let fpB = fingerprints[j]

                // Fast check 1: dHash Hamming distance
                let dHashDist = Self.hammingDistance(fpA.dHash, fpB.dHash)
                guard dHashDist <= PhotoMatchClassification.maxDuplicateDHashDistance else {
                    // dHash > 4 means images have different content or are merely similar
                    continue
                }

                // Check 2: Vision feature print distance
                var visionDistance: Float = 0
                do {
                    try fpA.fp.computeDistance(&visionDistance, to: fpB.fp)
                    let classification = PhotoMatchClassification.classify(
                        visionDistance: visionDistance,
                        dHashDistance: dHashDist
                    )

                    // Strictly include ONLY duplicates. Similar photos are excluded!
                    if classification == .duplicate {
                        let rootA = find(i)
                        let rootB = find(j)
                        if rootA != rootB {
                            parent[rootA] = rootB
                        }
                    }
                } catch {
                    // Treat as non-duplicate on error
                }
            }
        }

        // Step C: Collect clusters into groups
        var clusters: [Int: [MediaAssetIndexRecord]] = [:]
        for (index, item) in fingerprints.enumerated() {
            clusters[find(index), default: []].append(item.record)
        }

        var groups: [DuplicatePhotoGroup] = []

        for members in clusters.values where members.count >= 2 {
            // Resolve file sizes for confirmed duplicate members if needed
            var resolvedMembers: [MediaAssetIndexRecord] = []
            for member in members {
                if let size = member.fileSize, size > 0 {
                    resolvedMembers.append(member)
                } else if let fetched = await mediaLibrary.fetchFileSize(for: member.id), fetched > 0 {
                    resolvedMembers.append(member.withFileSize(fetched))
                } else {
                    resolvedMembers.append(member)
                }
            }

            // Best quality first: largest file size, then highest pixel count
            let sorted = resolvedMembers.sorted {
                let size0 = $0.fileSize ?? 0
                let size1 = $1.fileSize ?? 0
                if size0 != size1 { return size0 > size1 }
                return ($0.pixelWidth * $0.pixelHeight) > ($1.pixelWidth * $1.pixelHeight)
            }

            groups.append(DuplicatePhotoGroup(id: sorted[0].id, photos: sorted))
        }

        return groups
    }

    // MARK: - Perceptual Difference Hash (dHash)

    /// Computes a 64-bit difference hash from a 9×8 grayscale rendering of the image.
    static func computeDHash(from cgImage: CGImage) -> UInt64? {
        let width = 9
        let height = 8
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var rawData = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        for y in 0..<height {
            let rowStart = y * width
            for x in 0..<(width - 1) {
                let left = rawData[rowStart + x]
                let right = rawData[rowStart + x + 1]
                hash = (hash << 1) | (left < right ? 1 : 0)
            }
        }
        return hash
    }

    /// Computes Hamming distance between two 64-bit hashes using hardware popcount.
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
