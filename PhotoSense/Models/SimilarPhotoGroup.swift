import Foundation

// MARK: - Result Types

/// A group of photos identified as visually similar (same scene, subject in different poses, or similar composition).
struct SimilarPhotoGroup: Identifiable, Sendable, Hashable {
    let id: String                          // Stable ID derived from the representative asset
    let photos: [MediaAssetIndexRecord]
    let averageSimilarity: Float            // Mean pairwise cosine similarity within the group

    /// The "best" representative photo to show as the group thumbnail (highest resolution, then largest file size).
    var representative: MediaAssetIndexRecord { photos[0] }

    /// Other similar shots in this group (candidates for review and cleanup).
    var secondaryPhotos: [MediaAssetIndexRecord] { Array(photos.dropFirst()) }

    var totalStorageBytes: Int64 {
        photos.compactMap(\.fileSize).reduce(0, +)
    }

    var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
    }

    var formattedAverageSimilarity: String {
        String(format: "%.0f%% match", averageSimilarity * 100)
    }
}

/// The complete result of a Similar Photos analysis pass.
struct SimilarPhotoAnalysisResult: Sendable, Equatable {
    let groups: [SimilarPhotoGroup]
    let analyzedPhotoCount: Int

    var similarGroupCount: Int { groups.count }

    /// Total count of secondary similar photos across all groups.
    var secondaryPhotoCount: Int { groups.reduce(0) { $0 + $1.secondaryPhotos.count } }

    var totalReclaimableBytes: Int64 {
        groups.flatMap(\.secondaryPhotos).compactMap(\.fileSize).reduce(0, +)
    }

    var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalReclaimableBytes, countStyle: .file)
    }

    /// Returns a new result with the specified asset IDs removed,
    /// pruning any groups that have fewer than 2 remaining photos.
    func removing(ids: Set<String>) -> SimilarPhotoAnalysisResult {
        let updatedGroups = groups.compactMap { group -> SimilarPhotoGroup? in
            let remaining = group.photos.filter { !ids.contains($0.id) }
            guard remaining.count >= 2 else { return nil }
            return SimilarPhotoGroup(
                id: group.id,
                photos: remaining,
                averageSimilarity: group.averageSimilarity
            )
        }
        return SimilarPhotoAnalysisResult(
            groups: updatedGroups,
            analyzedPhotoCount: analyzedPhotoCount
        )
    }
}
