import Accelerate
import Foundation
import Photos
import UIKit
@preconcurrency import Vision

// MARK: - Configuration

/// Configurable tuning parameters for Similar Photos detection.
///
/// Every threshold is documented and exposed to allow calibration against real gallery datasets.
struct SimilarPhotoConfiguration: Sendable {

    /// The minimum cosine similarity required for two photo feature embeddings to be considered visually similar.
    ///
    /// Metric scale:
    /// - `1.000`: Identical vector.
    /// - `0.985 - 1.000`: True duplicates or slight re-encodings (handled by Duplicate Photos, excluded here).
    /// - `0.850 - 0.960`: Genuinely different shots of the same subject (different poses, burst shots, same scene/composition).
    /// - `0.700 - 0.800`: Weak similarity; high risk of false positives from shared ambient colors or backgrounds.
    /// - `< 0.700`: Unrelated content.
    ///
    /// Default: `0.86` ensures high subject/scene concordance and rejects false positives from background colors alone.
    public var similarityThreshold: Float = 0.86

    /// Upper threshold above which two photos are considered true duplicates rather than merely "similar".
    /// When combined with low perceptual hash difference, pairs crossing this ceiling are excluded from Similar Photos.
    public var duplicateCosineCeiling: Float = 0.985

    /// Maximum Hamming distance on 64-bit dHash for true duplicate exclusion.
    public var maxDuplicateDHashDistance: Int = 4

    /// Maximum aspect ratio divergence (ratio between max aspect ratio and min aspect ratio).
    /// Prevents pairing widely divergent compositions (e.g. extreme panorama vs vertical portrait).
    public var maxAspectRatioDivergence: Double = 0.35

    /// Thumbnail resolution passed to Apple Vision feature print generation.
    /// 299×299 matches the standard CNN input dimensions for feature extraction.
    public var featureTargetSize: CGSize = CGSize(width: 299, height: 299)

    /// Concurrency limit for background thumbnail fetching to protect system memory.
    public var concurrencyLimit: Int = 8

    public static let `default` = SimilarPhotoConfiguration()
}

// MARK: - In-Memory Feature Vector Cache

/// Actor-isolated cache that retains normalized feature vectors across the app session.
/// Avoids re-requesting PhotoKit thumbnails and re-running Vision feature print extraction
/// when navigating between screens or refreshing results.
actor SimilarPhotoFeatureCache {
    static let shared = SimilarPhotoFeatureCache()

    private var cache: [String: [Float]] = [:]

    func vector(for assetId: String) -> [Float]? {
        cache[assetId]
    }

    func store(vector: [Float], for assetId: String) {
        cache[assetId] = vector
    }

    func storeBatch(_ entries: [(String, [Float])]) {
        for (id, vec) in entries {
            cache[id] = vec
        }
    }

    func cachedAssetIDs() -> Set<String> {
        Set(cache.keys)
    }

    func clear() {
        cache.removeAll()
    }
}

// MARK: - Protocol

protocol SimilarPhotoAnalyzing: Sendable {
    func analyzePhotos(
        from records: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding,
        duplicateAssetIDs: Set<String>
    ) async throws -> SimilarPhotoAnalysisResult
}

// MARK: - Analysis Engine

/// High-performance Vision-based Similar Photo Analysis Engine.
///
/// **Workflow**:
/// 1. **Deduplication Filtering**:
///    Excludes photos already identified as true duplicates by `DuplicatePhotosSessionService`
///    or crossing the duplicate ceiling (`cosineSimilarity ≥ 0.985` with `dHash ≤ 4`).
///
/// 2. **Vision Feature Embedding Extraction**:
///    For each photo, checks the in-memory `SimilarPhotoFeatureCache`. Uncached photos load small
///    thumbnails and generate a dense neural feature vector using `VNGenerateImageFeaturePrintRequest`.
///    The raw float vector is normalized to unit length ($L_2$ norm) and cached.
///
/// 3. **Cosine Similarity Evaluation**:
///    Feature vectors are compared using hardware-accelerated dot product (`vDSP_dotpr`):
///    $$\text{Cosine Similarity} = \frac{A \cdot B}{\|A\|_2 \|B\|_2} = A_{\text{norm}} \cdot B_{\text{norm}}$$
///    Pairs crossing `configuration.similarityThreshold` (default `0.86`) are verified.
///
/// 4. **Semantic Clustering**:
///    Pairs are clustered using Union-Find into cohesive similarity groups.
///    Groups calculate their average internal similarity score and designate the highest resolution
///    copy as the representative photo.
actor SimilarPhotoAnalysisEngine: SimilarPhotoAnalyzing {

    private let configuration: SimilarPhotoConfiguration
    private let featureCache: SimilarPhotoFeatureCache
    private let analysisCache: MediaAnalysisCacheStore

    init(
        configuration: SimilarPhotoConfiguration = .default,
        featureCache: SimilarPhotoFeatureCache = .shared,
        analysisCache: MediaAnalysisCacheStore = .shared
    ) {
        self.configuration = configuration
        self.featureCache = featureCache
        self.analysisCache = analysisCache
    }

    func analyzePhotos(
        from records: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding,
        duplicateAssetIDs: Set<String> = []
    ) async throws -> SimilarPhotoAnalysisResult {
        try Task.checkCancellation()

        // Filter: photos only, and exclude confirmed true duplicate extra copies
        let photoRecords = records.filter { record in
            record.kind == .photo && !duplicateAssetIDs.contains(record.id)
        }

        guard photoRecords.count >= 2 else {
            return SimilarPhotoAnalysisResult(groups: [], analyzedPhotoCount: photoRecords.count)
        }

        // Step 1: Extract or retrieve cached Vision feature vectors
        let embeddedPhotos = try await extractFeatureEmbeddings(
            for: photoRecords,
            mediaLibrary: mediaLibrary
        )

        guard embeddedPhotos.count >= 2 else {
            return SimilarPhotoAnalysisResult(groups: [], analyzedPhotoCount: photoRecords.count)
        }

        try Task.checkCancellation()

        // Step 2: Pairwise cosine similarity comparison & clustering
        let groups = await clusterSimilarPhotos(from: embeddedPhotos, mediaLibrary: mediaLibrary)

        return SimilarPhotoAnalysisResult(
            groups: groups,
            analyzedPhotoCount: photoRecords.count
        )
    }

    // MARK: - Feature Embedding Extraction

    private struct EmbeddedPhoto: Sendable {
        let record: MediaAssetIndexRecord
        let featureVector: [Float]
        let dHash: UInt64?
    }

    private func extractFeatureEmbeddings(
        for records: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding
    ) async throws -> [EmbeddedPhoto] {
        var embedded: [EmbeddedPhoto] = []
        embedded.reserveCapacity(records.count)

        var uncachedRecords: [MediaAssetIndexRecord] = []

        // Check persistent cache first, then the in-memory session cache.
        for record in records {
            if let cached = await analysisCache.cachedSimilarPhotoFingerprint(for: record) {
                await featureCache.store(vector: cached.vector, for: record.id)
                embedded.append(
                    EmbeddedPhoto(
                        record: record,
                        featureVector: cached.vector,
                        dHash: cached.dHash
                    )
                )
            } else if let cachedVec = await featureCache.vector(for: record.id) {
                embedded.append(
                    EmbeddedPhoto(
                        record: record,
                        featureVector: cachedVec,
                        dHash: nil
                    )
                )
            } else {
                uncachedRecords.append(record)
            }
        }

        guard !uncachedRecords.isEmpty else {
            return embedded
        }

        // Process uncached records in bounded batches
        let targetSize = configuration.featureTargetSize
        let limit = configuration.concurrencyLimit

        for chunkStart in stride(from: 0, to: uncachedRecords.count, by: limit) {
            try Task.checkCancellation()
            let chunkEnd = min(chunkStart + limit, uncachedRecords.count)
            let chunk = Array(uncachedRecords[chunkStart..<chunkEnd])

            // Fetch thumbnails concurrently
            let chunkImages: [(MediaAssetIndexRecord, UIImage)] = await withTaskGroup(
                of: (MediaAssetIndexRecord, UIImage)?.self
            ) { group in
                for record in chunk {
                    let assetId = record.id
                    group.addTask {
                        guard let img = await ThumbnailPipeline.shared.thumbnail(
                            for: assetId,
                            targetSize: targetSize
                        ) else { return nil }
                        return (record, img)
                    }
                }

                var results: [(MediaAssetIndexRecord, UIImage)] = []
                for await res in group {
                    if let r = res { results.append(r) }
                }
                return results
            }

            // Generate Vision feature embeddings synchronously on the actor
            var newlyCached: [(String, [Float])] = []
            var persistentUpdates: [(record: MediaAssetIndexRecord, vector: [Float], dHash: UInt64?)] = []

            for (record, image) in chunkImages {
                guard let cgImage = image.cgImage else { continue }

                let request = VNGenerateImageFeaturePrintRequest()
                request.imageCropAndScaleOption = .scaleFill

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                    if let observation = request.results?.first as? VNFeaturePrintObservation,
                       let vector = Self.extractNormalizedVector(from: observation) {
                        let dHash = DuplicatePhotoAnalysisEngine.computeDHash(from: cgImage)
                        let item = EmbeddedPhoto(record: record, featureVector: vector, dHash: dHash)
                        embedded.append(item)
                        newlyCached.append((record.id, vector))
                        persistentUpdates.append((record: record, vector: vector, dHash: dHash))
                    }
                } catch {
                    // Skip if Vision extraction fails for this asset
                }
            }

            // Cache newly computed vectors
            await featureCache.storeBatch(newlyCached)
            await analysisCache.storeSimilarPhotoFingerprints(persistentUpdates)
            await Task.yield()
        }

        return embedded
    }

    // MARK: - Cosine Similarity & Clustering

    private func clusterSimilarPhotos(
        from items: [EmbeddedPhoto],
        mediaLibrary: any MediaLibraryProviding
    ) async -> [SimilarPhotoGroup] {
        let count = items.count
        guard count >= 2 else { return [] }

        var parent = Array(0..<count)

        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }

        // Track pairwise similarities to compute group mean similarity
        var pairSimilarities: [Set<Int>: Float] = [:]

        let threshold = configuration.similarityThreshold
        let duplicateCeiling = configuration.duplicateCosineCeiling
        let maxDHashDist = configuration.maxDuplicateDHashDistance
        let maxAspectDivergence = configuration.maxAspectRatioDivergence

        for i in 0..<count {
            let itemA = items[i]
            let vecA = itemA.featureVector
            let aspectA = aspectRatio(for: itemA.record)

            for j in (i + 1)..<count {
                let itemB = items[j]
                let aspectB = aspectRatio(for: itemB.record)

                // Aspect ratio check: avoid pairing extreme portrait with extreme landscape
                if abs(aspectA - aspectB) > maxAspectDivergence {
                    continue
                }

                // Compute Cosine Similarity using hardware-accelerated dot product
                let similarity = Self.cosineSimilarity(vecA, itemB.featureVector)

                // Check against configured similarity threshold
                guard similarity >= threshold else {
                    continue
                }

                // Check if this pair is actually a TRUE DUPLICATE rather than similar
                if similarity >= duplicateCeiling {
                    if let hashA = itemA.dHash, let hashB = itemB.dHash {
                        let dDist = DuplicatePhotoAnalysisEngine.hammingDistance(hashA, hashB)
                        if dDist <= maxDHashDist {
                            // True duplicate: exclude from Similar Photos
                            continue
                        }
                    }
                }

                // Pair is verified as similar
                let pairKey: Set<Int> = [i, j]
                pairSimilarities[pairKey] = similarity

                let rootA = find(i)
                let rootB = find(j)
                if rootA != rootB {
                    parent[rootA] = rootB
                }
            }
        }

        // Group into clusters
        var clusters: [Int: [Int]] = [:]
        for i in 0..<count {
            clusters[find(i), default: []].append(i)
        }

        var resultGroups: [SimilarPhotoGroup] = []

        for memberIndices in clusters.values where memberIndices.count >= 2 {
            let memberItems = memberIndices.map { items[$0] }

            // Compute average similarity among members in this cluster
            var totalSim: Float = 0
            var simCount = 0
            for a in 0..<memberIndices.count {
                for b in (a + 1)..<memberIndices.count {
                    let key: Set<Int> = [memberIndices[a], memberIndices[b]]
                    if let sim = pairSimilarities[key] {
                        totalSim += sim
                        simCount += 1
                    }
                }
            }
            let avgSimilarity = simCount > 0 ? (totalSim / Float(simCount)) : threshold

            // Resolve file size on-demand for members in confirmed groups if needed
            var resolvedRecords: [MediaAssetIndexRecord] = []
            for member in memberItems {
                let rec = member.record
                if let size = rec.fileSize, size > 0 {
                    resolvedRecords.append(rec)
                } else if let fetched = await mediaLibrary.fetchFileSize(for: rec.id), fetched > 0 {
                    resolvedRecords.append(rec.withFileSize(fetched))
                } else {
                    resolvedRecords.append(rec)
                }
            }

            // Best quality first: highest pixel count, then largest file size
            let sorted = resolvedRecords.sorted {
                let p0 = $0.pixelWidth * $0.pixelHeight
                let p1 = $1.pixelWidth * $1.pixelHeight
                if p0 != p1 { return p0 > p1 }
                return ($0.fileSize ?? 0) > ($1.fileSize ?? 0)
            }

            resultGroups.append(
                SimilarPhotoGroup(
                    id: sorted[0].id,
                    photos: sorted,
                    averageSimilarity: avgSimilarity
                )
            )
        }

        // Sort groups: largest storage footprint first
        resultGroups.sort { $0.totalStorageBytes > $1.totalStorageBytes }

        return resultGroups
    }

    // MARK: - Mathematical Helpers

    /// Computes the cosine similarity between two unit-normalized vectors using Accelerate `vDSP_dotpr`.
    ///
    /// For unit vectors $\|A\|_2 = \|B\|_2 = 1$:
    /// $$\cos(\theta) = A \cdot B$$
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        return max(-1.0, min(1.0, dotProduct))
    }

    /// Extracts and normalizes a float vector from `VNFeaturePrintObservation` to unit length ($L_2$ norm).
    static func extractNormalizedVector(from observation: VNFeaturePrintObservation) -> [Float]? {
        let count = observation.elementCount
        guard count > 0 else { return nil }

        let rawVector: [Float] = observation.data.withUnsafeBytes { buffer in
            let typed = buffer.bindMemory(to: Float.self)
            return Array(typed.prefix(count))
        }

        guard !rawVector.isEmpty else { return nil }

        // Compute L2 norm
        var sumSquares: Float = 0
        vDSP_svesq(rawVector, 1, &sumSquares, vDSP_Length(rawVector.count))
        let norm = sqrt(sumSquares)

        guard norm > 0 else { return nil }

        // Divide by norm to create unit vector
        var normalized = [Float](repeating: 0, count: rawVector.count)
        var divisor = norm
        vDSP_vsdiv(rawVector, 1, &divisor, &normalized, 1, vDSP_Length(rawVector.count))

        return normalized
    }

    private func aspectRatio(for record: MediaAssetIndexRecord) -> Double {
        let w = Double(max(1, record.pixelWidth))
        let h = Double(max(1, record.pixelHeight))
        return max(w, h) / min(w, h)
    }
}
