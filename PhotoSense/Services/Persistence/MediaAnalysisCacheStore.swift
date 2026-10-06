import Foundation
@preconcurrency import Vision

enum MediaAnalysisStatus: String, Codable, Sendable {
    case ready
    case failed
}

struct MediaAnalysisAssetSignature: Codable, Equatable, Hashable, Sendable {
    let id: String
    let kind: MediaAssetKind
    let modificationDate: Date?
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let fileSize: Int64?
    let uniformTypeIdentifiers: [String]
    let originalFilenames: [String]

    init(record: MediaAssetIndexRecord) {
        self.id = record.id
        self.kind = record.kind
        self.modificationDate = record.modificationDate
        self.creationDate = record.creationDate
        self.pixelWidth = record.pixelWidth
        self.pixelHeight = record.pixelHeight
        self.duration = record.duration
        self.fileSize = record.fileSize
        self.uniformTypeIdentifiers = record.uniformTypeIdentifiers.sorted()
        self.originalFilenames = record.originalFilenames.sorted()
    }
}

struct CachedPhotoAnalysis: Codable, Sendable {
    let assetId: String
    let signature: MediaAnalysisAssetSignature
    var status: MediaAnalysisStatus
    var dHash: UInt64?
    var duplicateFeaturePrintData: Data?
    var similarFeatureVectorData: Data?
    var analyzedAt: Date

    func matches(_ record: MediaAssetIndexRecord) -> Bool {
        signature == MediaAnalysisAssetSignature(record: record)
    }
}

struct CachedVideoAnalysis: Codable, Sendable {
    let assetId: String
    let signature: MediaAnalysisAssetSignature
    var status: MediaAnalysisStatus
    var featurePrintDataList: [Data]
    var analyzedAt: Date

    func matches(_ record: MediaAssetIndexRecord) -> Bool {
        signature == MediaAnalysisAssetSignature(record: record)
    }
}

struct PersistentMediaAnalysisCache: Codable, Sendable {
    var schemaVersion: Int
    var photos: [String: CachedPhotoAnalysis]
    var videos: [String: CachedVideoAnalysis]

    static let currentSchemaVersion = 1

    static var empty: PersistentMediaAnalysisCache {
        PersistentMediaAnalysisCache(
            schemaVersion: currentSchemaVersion,
            photos: [:],
            videos: [:]
        )
    }
}

actor MediaAnalysisCacheStore {
    static let shared = MediaAnalysisCacheStore()

    private let fileURL: URL
    private var cache: PersistentMediaAnalysisCache?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = URL.applicationSupportDirectory
                .appending(path: "MediaAnalysisCache")
                .appending(path: "analysis-cache.json")
        }
        encoder.outputFormatting = [.sortedKeys]
    }

    func cachedDuplicatePhotoFingerprintData(for record: MediaAssetIndexRecord) async -> (dHash: UInt64, featurePrintData: Data)? {
        guard let entry = await validPhotoEntry(for: record),
              let dHash = entry.dHash,
              let data = entry.duplicateFeaturePrintData else {
            return nil
        }
        return (dHash, data)
    }

    func cachedSimilarPhotoFingerprint(for record: MediaAssetIndexRecord) async -> (vector: [Float], dHash: UInt64?)? {
        guard let entry = await validPhotoEntry(for: record),
              let data = entry.similarFeatureVectorData,
              let vector = Self.floatArray(from: data) else {
            return nil
        }
        return (vector, entry.dHash)
    }

    func cachedVideoFeaturePrintDataList(for record: MediaAssetIndexRecord) async -> [Data]? {
        guard let entry = await validVideoEntry(for: record), entry.featurePrintDataList.count >= 4 else {
            return nil
        }
        return entry.featurePrintDataList
    }

    func duplicatePhotoRecordsNeedingAnalysis(from records: [MediaAssetIndexRecord]) async -> [MediaAssetIndexRecord] {
        await recordsNeedingPhotoAnalysis(from: records) { entry in
            entry.dHash == nil || entry.duplicateFeaturePrintData == nil
        }
    }

    func similarPhotoRecordsNeedingAnalysis(from records: [MediaAssetIndexRecord]) async -> [MediaAssetIndexRecord] {
        await recordsNeedingPhotoAnalysis(from: records) { entry in
            entry.similarFeatureVectorData == nil || entry.dHash == nil
        }
    }

    func videoRecordsNeedingAnalysis(from records: [MediaAssetIndexRecord]) async -> [MediaAssetIndexRecord] {
        let cache = await loadCache()
        return records.filter { record in
            guard record.kind == .video,
                  let entry = cache.videos[record.id],
                  entry.status == .ready,
                  entry.matches(record),
                  entry.featurePrintDataList.count >= 4 else {
                return record.kind == .video
            }
            return false
        }
    }

    func storeDuplicatePhotoFingerprints(_ entries: [(record: MediaAssetIndexRecord, dHash: UInt64, featurePrint: VNFeaturePrintObservation)]) async {
        guard !entries.isEmpty else { return }
        var cache = await loadCache()
        let now = Date()

        for entry in entries {
            var cached = cache.photos[entry.record.id] ?? CachedPhotoAnalysis(
                assetId: entry.record.id,
                signature: MediaAnalysisAssetSignature(record: entry.record),
                status: .ready,
                analyzedAt: now
            )
            cached.status = .ready
            cached.dHash = entry.dHash
            cached.duplicateFeaturePrintData = Self.archiveFeaturePrint(entry.featurePrint)
            cached.analyzedAt = now
            cache.photos[entry.record.id] = cached
        }

        await save(cache)
    }

    func storeSimilarPhotoFingerprints(_ entries: [(record: MediaAssetIndexRecord, vector: [Float], dHash: UInt64?)]) async {
        guard !entries.isEmpty else { return }
        var cache = await loadCache()
        let now = Date()

        for entry in entries {
            var cached = cache.photos[entry.record.id] ?? CachedPhotoAnalysis(
                assetId: entry.record.id,
                signature: MediaAnalysisAssetSignature(record: entry.record),
                status: .ready,
                analyzedAt: now
            )
            cached.status = .ready
            if let dHash = entry.dHash {
                cached.dHash = dHash
            }
            cached.similarFeatureVectorData = Self.data(from: entry.vector)
            cached.analyzedAt = now
            cache.photos[entry.record.id] = cached
        }

        await save(cache)
    }

    func storeVideoFeaturePrints(_ entries: [(record: MediaAssetIndexRecord, featurePrints: [VNFeaturePrintObservation])]) async {
        guard !entries.isEmpty else { return }
        var cache = await loadCache()
        let now = Date()

        for entry in entries {
            let archived = entry.featurePrints.compactMap(Self.archiveFeaturePrint)
            guard archived.count >= 4 else { continue }
            cache.videos[entry.record.id] = CachedVideoAnalysis(
                assetId: entry.record.id,
                signature: MediaAnalysisAssetSignature(record: entry.record),
                status: .ready,
                featurePrintDataList: archived,
                analyzedAt: now
            )
        }

        await save(cache)
    }

    func prune(toCurrentAssetIDs currentIDs: Set<String>) async {
        var cache = await loadCache()
        let oldPhotoCount = cache.photos.count
        let oldVideoCount = cache.videos.count

        cache.photos = cache.photos.filter { currentIDs.contains($0.key) }
        cache.videos = cache.videos.filter { currentIDs.contains($0.key) }

        if cache.photos.count != oldPhotoCount || cache.videos.count != oldVideoCount {
            await save(cache)
        }
    }

    private func recordsNeedingPhotoAnalysis(
        from records: [MediaAssetIndexRecord],
        missing: (CachedPhotoAnalysis) -> Bool
    ) async -> [MediaAssetIndexRecord] {
        let cache = await loadCache()
        return records.filter { record in
            guard record.kind == .photo,
                  let entry = cache.photos[record.id],
                  entry.status == .ready,
                  entry.matches(record) else {
                return record.kind == .photo
            }
            return missing(entry)
        }
    }

    private func validPhotoEntry(for record: MediaAssetIndexRecord) async -> CachedPhotoAnalysis? {
        let cache = await loadCache()
        guard let entry = cache.photos[record.id],
              entry.status == .ready,
              entry.matches(record) else {
            return nil
        }
        return entry
    }

    private func validVideoEntry(for record: MediaAssetIndexRecord) async -> CachedVideoAnalysis? {
        let cache = await loadCache()
        guard let entry = cache.videos[record.id],
              entry.status == .ready,
              entry.matches(record) else {
            return nil
        }
        return entry
    }

    private func loadCache() async -> PersistentMediaAnalysisCache {
        if let cache {
            return cache
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode(PersistentMediaAnalysisCache.self, from: data)
            guard decoded.schemaVersion == PersistentMediaAnalysisCache.currentSchemaVersion else {
                cache = .empty
                return .empty
            }
            cache = decoded
            return decoded
        } catch {
            cache = .empty
            return .empty
        }
    }

    private func save(_ updatedCache: PersistentMediaAnalysisCache) async {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(updatedCache)
            try data.write(to: fileURL, options: [.atomic])
            cache = updatedCache
        } catch {
            cache = updatedCache
        }
    }

    static func archiveFeaturePrint(_ observation: VNFeaturePrintObservation) -> Data? {
        try? NSKeyedArchiver.archivedData(
            withRootObject: observation,
            requiringSecureCoding: true
        )
    }

    static func unarchiveFeaturePrint(from data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: VNFeaturePrintObservation.self,
            from: data
        )
    }

    static func data(from floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func floatArray(from data: Data) -> [Float]? {
        guard data.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            return nil
        }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}

extension MediaAssetIndexRecord {
    var analysisSignature: MediaAnalysisAssetSignature {
        MediaAnalysisAssetSignature(record: self)
    }

    var analysisKeyComponent: String {
        [
            id,
            kind.rawValue,
            String(modificationDate?.timeIntervalSinceReferenceDate ?? -1),
            String(creationDate?.timeIntervalSinceReferenceDate ?? -1),
            String(pixelWidth),
            String(pixelHeight),
            String(duration),
            String(fileSize ?? -1),
            uniformTypeIdentifiers.sorted().joined(separator: ","),
            originalFilenames.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }
}
