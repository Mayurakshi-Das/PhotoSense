import Foundation
import Observation

/// In-memory session service that acts as the single source of truth for Duplicate Photos
/// analysis state and results during the current app session.
///
/// Guarantees:
/// 1. Duplicate analysis runs only once per app session (unless explicitly rescanned).
/// 2. Once analysis completes, the result is retained in memory for instant reuse.
/// 3. Navigating back and forth between Dashboard and Duplicate Photos never restarts analysis.
/// 4. Dashboard and Duplicate Photos screens observe this exact same state.
@MainActor
@Observable
final class DuplicatePhotosSessionService {
    static let shared = DuplicatePhotosSessionService()

    enum State: Equatable {
        case notAnalyzed
        case analyzing
        case ready(DuplicatePhotoAnalysisResult)
        case empty
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.notAnalyzed, .notAnalyzed), (.analyzing, .analyzing), (.empty, .empty):
                return true
            case (.ready(let a), .ready(let b)):
                return a.groups == b.groups
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    private(set) var state: State = .notAnalyzed

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private let engine: any DuplicatePhotoAnalyzing
    @ObservationIgnored private let mediaLibrary: any MediaLibraryProviding
    @ObservationIgnored private let analysisCache: MediaAnalysisCacheStore
    @ObservationIgnored private var analyzedKey: String?
    @ObservationIgnored private var inFlightKey: String?
    @ObservationIgnored private var analysisRevision = 0

    init(
        engine: any DuplicatePhotoAnalyzing = DuplicatePhotoAnalysisEngine(),
        mediaLibrary: any MediaLibraryProviding = PhotoKitMediaLibraryService(),
        analysisCache: MediaAnalysisCacheStore = .shared
    ) {
        self.engine = engine
        self.mediaLibrary = mediaLibrary
        self.analysisCache = analysisCache
    }

    /// Triggers duplicate analysis only if it has not yet run in this app session.
    /// If analysis is already completed (.ready or .empty) or in progress (.analyzing),
    /// this returns immediately without re-analyzing or re-fetching photos.
    func analyzeIfNeeded(with records: [MediaAssetIndexRecord]) {
        let key = Self.analysisKey(for: records)
        guard analyzedKey != key, inFlightKey != key else {
            return
        }

        startAnalysis(with: records, key: key, forceLoadingState: false)
    }

    /// Explicitly forces a re-analysis (e.g. from a user "Re-scan" button).
    func forceAnalyze(with records: [MediaAssetIndexRecord]) {
        startAnalysis(with: records, key: Self.analysisKey(for: records), forceLoadingState: true)
    }

    private func startAnalysis(
        with records: [MediaAssetIndexRecord],
        key: String,
        forceLoadingState: Bool
    ) {
        analysisTask?.cancel()
        analysisRevision += 1
        let revision = analysisRevision
        inFlightKey = key

        if forceLoadingState {
            state = .analyzing
        }

        analysisTask = Task {
            do {
                let candidateRecords = Self.duplicateCandidateRecords(in: records)
                let missingRecords = await analysisCache.duplicatePhotoRecordsNeedingAnalysis(from: candidateRecords)
                guard !Task.isCancelled, revision == analysisRevision else { return }
                if forceLoadingState || !missingRecords.isEmpty {
                    state = .analyzing
                }

                let result = try await engine.analyzePhotos(from: records, mediaLibrary: mediaLibrary)
                guard !Task.isCancelled, revision == analysisRevision else { return }
                analyzedKey = key
                inFlightKey = nil
                if result.groups.isEmpty {
                    state = .empty
                } else {
                    state = .ready(result)
                }
                SimilarPhotosSessionService.shared.analyzeIfNeeded(with: records)
            } catch is CancellationError {
                if revision == analysisRevision, state == .analyzing {
                    state = .notAnalyzed
                }
            } catch {
                guard !Task.isCancelled, revision == analysisRevision else { return }
                inFlightKey = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Removes deleted assets from the existing session result, keeping UI & Dashboard updated
    /// without re-running duplicate detection.
    func removeDeletedAssets(ids: Set<String>) {
        guard case .ready(let result) = state else { return }
        let updatedResult = result.removing(ids: ids)
        if updatedResult.groups.isEmpty {
            state = .empty
        } else {
            state = .ready(updatedResult)
        }
    }

    private static func analysisKey(for records: [MediaAssetIndexRecord]) -> String {
        records
            .filter { $0.kind == .photo }
            .map(\.analysisKeyComponent)
            .sorted()
            .joined(separator: "\n")
    }

    private static func duplicateCandidateRecords(in records: [MediaAssetIndexRecord]) -> [MediaAssetIndexRecord] {
        struct BucketKey: Hashable {
            let aspectRatioTier: Int
            let resolutionTier: Int
        }

        var buckets: [BucketKey: [MediaAssetIndexRecord]] = [:]
        for record in records where record.kind == .photo {
            let w = max(1, record.pixelWidth)
            let h = max(1, record.pixelHeight)
            let ratio = Double(max(w, h)) / Double(min(w, h))
            let megaPixels = (Double(w) * Double(h)) / 1_000_000.0
            let key = BucketKey(
                aspectRatioTier: Int(round(ratio * 100)),
                resolutionTier: Int(round(megaPixels * 2))
            )
            buckets[key, default: []].append(record)
        }

        return buckets.values
            .filter { $0.count >= 2 }
            .flatMap { $0 }
    }
}
