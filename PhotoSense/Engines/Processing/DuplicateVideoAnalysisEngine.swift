@preconcurrency import AVFoundation
@preconcurrency import Vision
import Foundation
import Photos
import UIKit

// MARK: - Result Types

/// A group of videos identified as duplicates of each other.
struct DuplicateVideoGroup: Identifiable, Sendable, Hashable {
    let id: String            // Stable ID derived from the representative asset
    let videos: [MediaAssetIndexRecord]

    /// The "best" representative video (highest resolution, then largest file size).
    var representative: MediaAssetIndexRecord { videos[0] }

    /// Extra copies suggested for deletion (all videos except the representative).
    var deletionCandidates: [MediaAssetIndexRecord] { Array(videos.dropFirst()) }

    var totalStorageBytes: Int64 {
        videos.compactMap(\.fileSize).reduce(0, +)
    }

    var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
    }
}

struct DuplicateVideoAnalysisResult: Sendable {
    let groups: [DuplicateVideoGroup]
    let analyzedVideoCount: Int

    var duplicateGroupCount: Int { groups.count }

    /// Total number of extra copies that can be reclaimed.
    var deletableCopyCount: Int { groups.reduce(0) { $0 + $1.deletionCandidates.count } }

    var totalReclaimableBytes: Int64 {
        groups.flatMap(\.deletionCandidates).compactMap(\.fileSize).reduce(0, +)
    }

    var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalReclaimableBytes, countStyle: .file)
    }

    /// Returns a new result with the specified asset IDs removed,
    /// pruning any groups that have fewer than 2 remaining videos.
    func removing(ids: Set<String>) -> DuplicateVideoAnalysisResult {
        let updatedGroups = groups.compactMap { group -> DuplicateVideoGroup? in
            let remaining = group.videos.filter { !ids.contains($0.id) }
            guard remaining.count >= 2 else { return nil }
            return DuplicateVideoGroup(id: group.id, videos: remaining)
        }
        return DuplicateVideoAnalysisResult(
            groups: updatedGroups,
            analyzedVideoCount: analyzedVideoCount
        )
    }
}

// MARK: - Protocol

protocol DuplicateVideoAnalyzing: Sendable {
    func analyzeVideos(
        from records: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding
    ) async throws -> DuplicateVideoAnalysisResult
}

// MARK: - Engine

/// Two-stage duplicate video detection:
///
/// **Stage 1 — Lightweight Metadata Grouping** (O(n log n), zero media decode)
///   Filters videos by close durations (within ±max(1.0s, 3%)) and matching aspect ratio
///   (within ±15% tolerance). This instantly eliminates non-candidates without disk or AV reads.
///
/// **Stage 2 — Multi-Point Keyframe Sampling & Vision Verification**
///   For likely candidates, extracts 5 normalized keyframes (10%, 30%, 50%, 70%, 90%)
///   at low resolution (160×160) using `AVAssetImageGenerator`.
///   Generates `VNFeaturePrintObservation` embeddings for each frame and requires:
///   1. Every sampled frame pair has embedding distance ≤ 0.22 (no single scene can mismatch).
///   2. The average embedding distance across all 5 points is ≤ 0.16.
///   Merely similar scenes or single matching frames are strictly rejected.
actor DuplicateVideoAnalysisEngine: DuplicateVideoAnalyzing {

    /// Maximum distance between corresponding frames (strict threshold).
    private let maxFrameDistance: Float = 0.22

    /// Maximum average distance across all sampled keyframes.
    private let maxAverageDistance: Float = 0.16

    /// Normalized sample points along the video duration.
    private let sampleFractions: [Double] = [0.10, 0.30, 0.50, 0.70, 0.90]

    /// Keyframe image size (bounded memory, fast extraction).
    private let keyframeTargetSize = CGSize(width: 160, height: 160)

    private let analysisCache: MediaAnalysisCacheStore

    init(analysisCache: MediaAnalysisCacheStore = .shared) {
        self.analysisCache = analysisCache
    }

    func analyzeVideos(
        from records: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding
    ) async throws -> DuplicateVideoAnalysisResult {
        try Task.checkCancellation()

        let videoRecords = records.filter { $0.kind == .video }
        guard videoRecords.count >= 2 else {
            return DuplicateVideoAnalysisResult(groups: [], analyzedVideoCount: videoRecords.count)
        }

        // ── Stage 1: Metadata candidate bucketing ─────────────────────────────────
        let candidateBuckets = buildCandidateBuckets(from: videoRecords)
        guard !candidateBuckets.isEmpty else {
            return DuplicateVideoAnalysisResult(groups: [], analyzedVideoCount: videoRecords.count)
        }

        try Task.checkCancellation()

        // ── Stage 2: Content verification on likely candidates ───────────────────
        var groups: [DuplicateVideoGroup] = []

        for bucket in candidateBuckets {
            try Task.checkCancellation()
            let bucketGroups = try await verifyVideoDuplicates(in: bucket, mediaLibrary: mediaLibrary)
            groups.append(contentsOf: bucketGroups)
            await Task.yield()
        }

        // Sort groups: largest storage impact first
        groups.sort { $0.totalStorageBytes > $1.totalStorageBytes }

        return DuplicateVideoAnalysisResult(
            groups: groups,
            analyzedVideoCount: videoRecords.count
        )
    }

    // MARK: - Stage 1: Metadata Bucketing

    private func buildCandidateBuckets(from records: [MediaAssetIndexRecord]) -> [[MediaAssetIndexRecord]] {
        // Sort by duration ascending
        let sorted = records.sorted { $0.duration < $1.duration }
        var parent = Array(0..<sorted.count)

        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }

        for i in 0..<sorted.count {
            let itemA = sorted[i]
            let durationA = itemA.duration
            let tolerance = max(1.0, durationA * 0.03) // 1.0s or 3% tolerance

            for j in (i + 1)..<sorted.count {
                let itemB = sorted[j]
                if (itemB.duration - durationA) > tolerance {
                    // Beyond duration tolerance, subsequent items will also exceed tolerance
                    break
                }

                // Check aspect ratio tolerance (orientation-independent)
                let ratioA = aspectRatio(for: itemA)
                let ratioB = aspectRatio(for: itemB)
                if abs(ratioA - ratioB) <= 0.25 {
                    let rootA = find(i)
                    let rootB = find(j)
                    if rootA != rootB {
                        parent[rootA] = rootB
                    }
                }
            }
        }

        var clusters: [Int: [MediaAssetIndexRecord]] = [:]
        for (index, record) in sorted.enumerated() {
            clusters[find(index), default: []].append(record)
        }

        return clusters.values
            .filter { $0.count >= 2 }
            .map { $0 }
    }

    private func aspectRatio(for record: MediaAssetIndexRecord) -> Double {
        let w = Double(record.pixelWidth)
        let h = Double(record.pixelHeight)
        guard w > 0, h > 0 else { return 1.0 }
        return max(w, h) / min(w, h)
    }

    // MARK: - Stage 2: Content Verification

    private struct VideoKeyframes: Sendable {
        let record: MediaAssetIndexRecord
        let frameDataList: [Data]
    }

    private func verifyVideoDuplicates(
        in bucket: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding
    ) async throws -> [DuplicateVideoGroup] {
        guard bucket.count >= 2 else { return [] }

        struct VideoFingerprints {
            let record: MediaAssetIndexRecord
            let prints: [VNFeaturePrintObservation]
        }

        var fingerprintedVideos: [VideoFingerprints] = []
        var uncachedRecords: [MediaAssetIndexRecord] = []

        for record in bucket {
            if let cachedDataList = await analysisCache.cachedVideoFeaturePrintDataList(for: record) {
                let cachedPrints = cachedDataList.compactMap(MediaAnalysisCacheStore.unarchiveFeaturePrint)
                if cachedPrints.count >= 4 {
                    fingerprintedVideos.append(VideoFingerprints(record: record, prints: cachedPrints))
                } else {
                    uncachedRecords.append(record)
                }
            } else {
                uncachedRecords.append(record)
            }
        }

        // Step A: Extract normalized keyframe images (bounded 160×160) only for cache misses.
        var sampledVideos: [VideoKeyframes] = []
        for record in uncachedRecords {
            try Task.checkCancellation()
            if let frames = await extractKeyframes(for: record) {
                sampledVideos.append(frames)
            }
            await Task.yield()
        }

        // Step B: Generate Vision feature prints synchronously on actor
        var cacheUpdates: [(record: MediaAssetIndexRecord, featurePrints: [VNFeaturePrintObservation])] = []

        for video in sampledVideos {
            try Task.checkCancellation()
            var observations: [VNFeaturePrintObservation] = []
            for data in video.frameDataList {
                autoreleasepool {
                    guard let image = UIImage(data: data), let cgImage = image.cgImage else { return }
                    let request = VNGenerateImageFeaturePrintRequest()
                    request.imageCropAndScaleOption = .scaleFill
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                    do {
                        try handler.perform([request])
                        if let observation = request.results?.first as? VNFeaturePrintObservation {
                            observations.append(observation)
                        }
                    } catch {
                        // Skip invalid frame
                    }
                }
            }

            // Require at least 4 successful frame observations out of 5
            if observations.count >= 4 {
                fingerprintedVideos.append(VideoFingerprints(record: video.record, prints: observations))
                cacheUpdates.append((record: video.record, featurePrints: observations))
            }
            await Task.yield()
        }

        await analysisCache.storeVideoFeaturePrints(cacheUpdates)

        guard fingerprintedVideos.count >= 2 else { return [] }

        // Step C: Pairwise comparison across all sampled frames
        var parent = Array(0..<fingerprintedVideos.count)

        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }

        for i in 0..<fingerprintedVideos.count {
            try Task.checkCancellation()
            for j in (i + 1)..<fingerprintedVideos.count {
                let vA = fingerprintedVideos[i]
                let vB = fingerprintedVideos[j]

                let compareCount = min(vA.prints.count, vB.prints.count)
                guard compareCount >= 4 else { continue }

                var distances: [Float] = []
                var anyFrameFailed = false

                for k in 0..<compareCount {
                    var d: Float = 0
                    do {
                        try vA.prints[k].computeDistance(&d, to: vB.prints[k])
                        if d > maxFrameDistance {
                            anyFrameFailed = true
                            break
                        }
                        distances.append(d)
                    } catch {
                        anyFrameFailed = true
                        break
                    }
                }

                if !anyFrameFailed, !distances.isEmpty {
                    let avgDistance = distances.reduce(0, +) / Float(distances.count)
                    if avgDistance <= maxAverageDistance {
                        let rootA = find(i)
                        let rootB = find(j)
                        if rootA != rootB { parent[rootA] = rootB }
                    }
                }
            }
            await Task.yield()
        }

        // Step D: Collect groups
        var clusters: [Int: [MediaAssetIndexRecord]] = [:]
        for (index, item) in fingerprintedVideos.enumerated() {
            clusters[find(index), default: []].append(item.record)
        }

        var groups: [DuplicateVideoGroup] = []

        for members in clusters.values where members.count >= 2 {
            try Task.checkCancellation()

            var resolvedMembers: [MediaAssetIndexRecord] = []
            resolvedMembers.reserveCapacity(members.count)
            for member in members {
                if let size = member.fileSize, size > 0 {
                    resolvedMembers.append(member)
                } else if let fetched = await mediaLibrary.fetchFileSize(for: member.id), fetched > 0 {
                    resolvedMembers.append(member.withFileSize(fetched))
                } else {
                    resolvedMembers.append(member)
                }
            }

            // Sort by highest resolution first, then largest file size first ("Best").
            // The remaining videos are the reclaimable deletion candidates.
            let sorted = resolvedMembers.sorted {
                let res0 = $0.pixelWidth * $0.pixelHeight
                let res1 = $1.pixelWidth * $1.pixelHeight
                if res0 != res1 { return res0 > res1 }
                return ($0.fileSize ?? 0) > ($1.fileSize ?? 0)
            }
            groups.append(DuplicateVideoGroup(id: sorted[0].id, videos: sorted))
        }

        return groups
    }

    // MARK: - Keyframe Extraction via AVAssetImageGenerator

    private func extractKeyframes(for record: MediaAssetIndexRecord) async -> VideoKeyframes? {
        let assetId = record.id
        let fractions = self.sampleFractions
        let targetSize = self.keyframeTargetSize

        return await Task.detached(priority: .userInitiated) {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            guard let phAsset = fetchResult.firstObject else { return nil }

            let options = PHVideoRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false

            let avAsset: AVAsset? = await withCheckedContinuation { continuation in
                PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, _ in
                    nonisolated(unsafe) let transferred = asset
                    continuation.resume(returning: transferred)
                }
            }

            guard let avAsset else { return nil }

            let totalSeconds = CMTimeGetSeconds(avAsset.duration)
            guard totalSeconds > 0.3 else { return nil }

            let generator = AVAssetImageGenerator(asset: avAsset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = targetSize
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

            var frameDataList: [Data] = []
            for fraction in fractions {
                let time = CMTime(seconds: totalSeconds * fraction, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    if let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) {
                        frameDataList.append(data)
                    }
                }
            }

            guard frameDataList.count >= 3 else { return nil }
            return VideoKeyframes(record: record, frameDataList: frameDataList)
        }.value
    }
}
