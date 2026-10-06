import Foundation
import Observation

/// In-memory session service acting as the single source of truth for Similar Photos
/// analysis state and results during the current app session.
///
/// Guarantees:
/// 1. Analysis runs only once per app session (unless explicitly rescanned).
/// 2. Results are retained in memory for instant reuse.
/// 3. True duplicates identified by `DuplicatePhotosSessionService` are strictly excluded.
/// 4. Navigating back and forth between screens never restarts analysis.
@MainActor
@Observable
final class SimilarPhotosSessionService {
    static let shared = SimilarPhotosSessionService()

    enum State: Equatable {
        case notAnalyzed
        case analyzing
        case ready(SimilarPhotoAnalysisResult)
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
    @ObservationIgnored private let engine: any SimilarPhotoAnalyzing
    @ObservationIgnored private let mediaLibrary: any MediaLibraryProviding
    @ObservationIgnored private let analysisCache: MediaAnalysisCacheStore
    @ObservationIgnored private var analyzedKey: String?
    @ObservationIgnored private var inFlightKey: String?
    @ObservationIgnored private var analysisRevision = 0

    init(
        engine: any SimilarPhotoAnalyzing = SimilarPhotoAnalysisEngine(),
        mediaLibrary: any MediaLibraryProviding = PhotoKitMediaLibraryService(),
        analysisCache: MediaAnalysisCacheStore = .shared
    ) {
        self.engine = engine
        self.mediaLibrary = mediaLibrary
        self.analysisCache = analysisCache
    }

    /// Triggers similar photos analysis only if it has not yet run in this app session.
    func analyzeIfNeeded(with records: [MediaAssetIndexRecord]) {
        let duplicateAssetIDs = currentDuplicateAssetIDs()
        let key = Self.analysisKey(for: records, duplicateAssetIDs: duplicateAssetIDs)
        guard analyzedKey != key, inFlightKey != key else {
            return
        }

        startAnalysis(
            with: records,
            key: key,
            duplicateAssetIDs: duplicateAssetIDs,
            forceLoadingState: false
        )
    }

    /// Explicitly forces a re-analysis.
    func forceAnalyze(with records: [MediaAssetIndexRecord]) {
        let duplicateAssetIDs = currentDuplicateAssetIDs()
        startAnalysis(
            with: records,
            key: Self.analysisKey(for: records, duplicateAssetIDs: duplicateAssetIDs),
            duplicateAssetIDs: duplicateAssetIDs,
            forceLoadingState: true
        )
    }

    private func startAnalysis(
        with records: [MediaAssetIndexRecord],
        key: String,
        duplicateAssetIDs: Set<String>,
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
                let missingRecords = await analysisCache.similarPhotoRecordsNeedingAnalysis(from: records)
                guard !Task.isCancelled, revision == analysisRevision else { return }
                if forceLoadingState || !missingRecords.isEmpty {
                    state = .analyzing
                }

                let result = try await engine.analyzePhotos(
                    from: records,
                    mediaLibrary: mediaLibrary,
                    duplicateAssetIDs: duplicateAssetIDs
                )
                guard !Task.isCancelled, revision == analysisRevision else { return }
                analyzedKey = key
                inFlightKey = nil

                if result.groups.isEmpty {
                    state = .empty
                } else {
                    state = .ready(result)
                }
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

    /// Updates session state in-place when assets are deleted, keeping UI and dashboard in sync.
    func removeDeletedAssets(ids: Set<String>) {
        guard case .ready(let result) = state else { return }
        let updated = result.removing(ids: ids)
        if updated.groups.isEmpty {
            state = .empty
        } else {
            state = .ready(updated)
        }
    }

    private func currentDuplicateAssetIDs() -> Set<String> {
        if case .ready(let dupResult) = DuplicatePhotosSessionService.shared.state {
            return Set(dupResult.groups.flatMap(\.photos).map(\.id))
        }
        return []
    }

    private static func analysisKey(
        for records: [MediaAssetIndexRecord],
        duplicateAssetIDs: Set<String>
    ) -> String {
        let recordKey = records
            .filter { $0.kind == .photo }
            .map(\.analysisKeyComponent)
            .sorted()
            .joined(separator: "\n")
        let duplicateKey = duplicateAssetIDs.sorted().joined(separator: "\n")
        return recordKey + "\n#duplicates\n" + duplicateKey
    }
}
