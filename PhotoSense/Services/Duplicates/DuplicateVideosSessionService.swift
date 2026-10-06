import Foundation
import Observation

/// In-memory session service acting as the single source of truth for Duplicate Videos
/// analysis state and results during the current app session.
///
/// Guarantees:
/// 1. Duplicate video analysis runs only once per app session (unless explicitly rescanned).
/// 2. The completed result is retained in memory for instant reuse.
/// 3. Navigating between Dashboard and Duplicate Videos screen never restarts analysis.
/// 4. Dashboard and detail screen observe this exact same state.
@MainActor
@Observable
final class DuplicateVideosSessionService {
    static let shared = DuplicateVideosSessionService()

    enum State: Equatable {
        case notAnalyzed
        case analyzing
        case ready(DuplicateVideoAnalysisResult)
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
    @ObservationIgnored private let engine: any DuplicateVideoAnalyzing
    @ObservationIgnored private let mediaLibrary: any MediaLibraryProviding
    @ObservationIgnored private let analysisCache: MediaAnalysisCacheStore
    @ObservationIgnored private var analyzedKey: String?
    @ObservationIgnored private var inFlightKey: String?
    @ObservationIgnored private var analysisRevision = 0

    init(
        engine: any DuplicateVideoAnalyzing = DuplicateVideoAnalysisEngine(),
        mediaLibrary: any MediaLibraryProviding = PhotoKitMediaLibraryService(),
        analysisCache: MediaAnalysisCacheStore = .shared
    ) {
        self.engine = engine
        self.mediaLibrary = mediaLibrary
        self.analysisCache = analysisCache
    }

    /// Triggers duplicate video analysis only if it has not yet run in this app session.
    func analyzeIfNeeded(with records: [MediaAssetIndexRecord]) {
        let key = Self.analysisKey(for: records)
        guard analyzedKey != key, inFlightKey != key else {
            return
        }

        startAnalysis(with: records, key: key, forceLoadingState: false)
    }

    /// Explicitly forces a re-analysis (e.g. from user "Re-scan" button).
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
                let missingRecords = await analysisCache.videoRecordsNeedingAnalysis(from: candidateRecords)
                guard !Task.isCancelled, revision == analysisRevision else { return }
                if forceLoadingState || !missingRecords.isEmpty {
                    state = .analyzing
                }

                let result = try await engine.analyzeVideos(from: records, mediaLibrary: mediaLibrary)
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

    /// Updates session state in-place when assets are deleted, keeping Dashboard and UI in sync.
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
            .filter { $0.kind == .video }
            .map(\.analysisKeyComponent)
            .sorted()
            .joined(separator: "\n")
    }

    private static func duplicateCandidateRecords(in records: [MediaAssetIndexRecord]) -> [MediaAssetIndexRecord] {
        let sorted = records
            .filter { $0.kind == .video }
            .sorted { $0.duration < $1.duration }

        guard sorted.count >= 2 else { return [] }

        var parent = Array(0..<sorted.count)

        func find(_ value: Int) -> Int {
            var value = value
            while parent[value] != value {
                parent[value] = parent[parent[value]]
                value = parent[value]
            }
            return value
        }

        func aspectRatio(for record: MediaAssetIndexRecord) -> Double {
            let w = Double(record.pixelWidth)
            let h = Double(record.pixelHeight)
            guard w > 0, h > 0 else { return 1.0 }
            return max(w, h) / min(w, h)
        }

        for i in 0..<sorted.count {
            let itemA = sorted[i]
            let tolerance = max(1.0, itemA.duration * 0.03)

            for j in (i + 1)..<sorted.count {
                let itemB = sorted[j]
                if (itemB.duration - itemA.duration) > tolerance {
                    break
                }

                if abs(aspectRatio(for: itemA) - aspectRatio(for: itemB)) <= 0.25 {
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
            .flatMap { $0 }
    }
}
