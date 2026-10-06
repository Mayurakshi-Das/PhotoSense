import Foundation

struct LargeVideoAnalysisResult: Sendable, Hashable {
    let allVideosSorted: [VideoAssetItem]
    let top15PercentVideos: [VideoAssetItem]
    let remainingVideos: [VideoAssetItem]
    let totalStorageBytes: Int64
    let top15StorageBytes: Int64
    let remainingStorageBytes: Int64

    var totalFormattedStorage: String {
        ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
    }

    var top15FormattedStorage: String {
        ByteCountFormatter.string(fromByteCount: top15StorageBytes, countStyle: .file)
    }

    var remainingFormattedStorage: String {
        ByteCountFormatter.string(fromByteCount: remainingStorageBytes, countStyle: .file)
    }

    var top15PercentageString: String {
        guard !allVideosSorted.isEmpty else { return "0%" }
        let pct = (Double(top15StorageBytes) / Double(max(1, totalStorageBytes))) * 100
        return String(format: "%.0f%%", pct)
    }

    /// Returns a new result with the given IDs removed, re-partitioning top-15% from the remaining items.
    func removing(ids: Set<String>) -> LargeVideoAnalysisResult {
        var remaining = allVideosSorted.filter { !ids.contains($0.id) }
        // Re-rank
        for i in 0..<remaining.count { remaining[i].rank = i + 1 }

        let topCount = remaining.isEmpty ? 0 : max(1, Int(ceil(Double(remaining.count) * 0.15)))
        let top15 = Array(remaining.prefix(topCount))
        let rest = Array(remaining.dropFirst(topCount))

        let total = remaining.reduce(Int64(0)) { $0 + $1.fileSize }
        let topBytes = top15.reduce(Int64(0)) { $0 + $1.fileSize }
        let restBytes = rest.reduce(Int64(0)) { $0 + $1.fileSize }

        return LargeVideoAnalysisResult(
            allVideosSorted: remaining,
            top15PercentVideos: top15,
            remainingVideos: rest,
            totalStorageBytes: total,
            top15StorageBytes: topBytes,
            remainingStorageBytes: restBytes
        )
    }
}

protocol LargeVideoAnalyzing: Sendable {
    func analyzeVideos(
        from records: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding
    ) async throws -> LargeVideoAnalysisResult
}

actor LargeVideoAnalysisEngine: LargeVideoAnalyzing {
    func analyzeVideos(
        from records: [MediaAssetIndexRecord],
        mediaLibrary: any MediaLibraryProviding
    ) async throws -> LargeVideoAnalysisResult {
        try Task.checkCancellation()

        let videoRecords = records.filter { $0.kind == .video }
        guard !videoRecords.isEmpty else {
            return LargeVideoAnalysisResult(
                allVideosSorted: [],
                top15PercentVideos: [],
                remainingVideos: [],
                totalStorageBytes: 0,
                top15StorageBytes: 0,
                remainingStorageBytes: 0
            )
        }

        // Resolve file size for each video using bounded concurrency
        var items: [VideoAssetItem] = []
        items.reserveCapacity(videoRecords.count)

        // Process in bounded chunks of 8 to avoid overwhelming the system
        let chunkSize = 8
        for chunkStart in stride(from: 0, to: videoRecords.count, by: chunkSize) {
            try Task.checkCancellation()
            let chunkEnd = min(chunkStart + chunkSize, videoRecords.count)
            let chunk = Array(videoRecords[chunkStart..<chunkEnd])

            let resolvedChunk = await withTaskGroup(of: VideoAssetItem.self) { group in
                for record in chunk {
                    group.addTask {
                        let size: Int64
                        if let cachedSize = record.fileSize, cachedSize > 0 {
                            size = cachedSize
                        } else if let fetched = await mediaLibrary.fetchFileSize(for: record.id), fetched > 0 {
                            size = fetched
                        } else {
                            // Fallback estimate: ~2.5 MB per second for standard 1080p/4K mobile video if completely inaccessible
                            size = max(500_000, Int64(record.duration * 2_500_000))
                        }

                        return VideoAssetItem(
                            id: record.id,
                            duration: record.duration,
                            fileSize: size,
                            creationDate: record.creationDate,
                            pixelWidth: record.pixelWidth,
                            pixelHeight: record.pixelHeight
                        )
                    }
                }

                var chunkResults: [VideoAssetItem] = []
                for await item in group {
                    chunkResults.append(item)
                }
                return chunkResults
            }

            items.append(contentsOf: resolvedChunk)
        }

        try Task.checkCancellation()

        // Sort largest to smallest
        items.sort { $0.fileSize > $1.fileSize }

        // Assign 1-indexed rank
        for i in 0..<items.count {
            items[i].rank = i + 1
        }

        // Calculate top 15% (at least 1 if videos exist)
        let topCount = max(1, Int(ceil(Double(items.count) * 0.15)))
        let top15 = Array(items.prefix(topCount))
        let remaining = Array(items.dropFirst(topCount))

        let totalBytes = items.reduce(Int64(0)) { $0 + $1.fileSize }
        let topBytes = top15.reduce(Int64(0)) { $0 + $1.fileSize }
        let remainingBytes = remaining.reduce(Int64(0)) { $0 + $1.fileSize }

        return LargeVideoAnalysisResult(
            allVideosSorted: items,
            top15PercentVideos: top15,
            remainingVideos: remaining,
            totalStorageBytes: totalBytes,
            top15StorageBytes: topBytes,
            remainingStorageBytes: remainingBytes
        )
    }
}
