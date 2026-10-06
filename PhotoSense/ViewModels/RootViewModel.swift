import Foundation
import Observation

@MainActor
@Observable
final class RootViewModel {
    enum State: Equatable {
        case idle
        case loadingIndex
        case checkingAuthorization
        case needsAuthorization(MediaLibraryAuthorizationStatus)
        case indexing(MediaLibraryAuthorizationStatus)
        case ready(MediaLibraryAuthorizationStatus, DashboardSnapshot)
        case failed(String)
    }

    var state: State = .idle

    @ObservationIgnored
    private let mediaLibrary: any MediaLibraryProviding

    @ObservationIgnored
    private let indexer: any MediaIndexing

    @ObservationIgnored
    private let dashboardProvider: any DashboardProviding

    @ObservationIgnored
    private var currentTask: Task<Void, Never>?

    @ObservationIgnored
    private let bootstrapError: String?

    init(
        mediaLibrary: any MediaLibraryProviding = PhotoKitMediaLibraryService(),
        indexer: (any MediaIndexing)? = nil,
        dashboardProvider: (any DashboardProviding)? = nil
    ) {
        self.mediaLibrary = mediaLibrary

        if let indexer, let dashboardProvider {
            self.indexer = indexer
            self.dashboardProvider = dashboardProvider
            self.bootstrapError = nil
            return
        }

        do {
            let indexStore = try SwiftDataMediaIndexStore()
            self.indexer = indexer ?? MediaIndexingService(
                mediaLibrary: mediaLibrary,
                indexStore: indexStore
            )
            self.dashboardProvider = dashboardProvider ?? DashboardService(indexStore: indexStore)
            self.bootstrapError = nil
        } catch {
            let reason = error.localizedDescription
            let unavailableStore = UnavailableMediaIndexStore(reason: reason)
            self.indexer = indexer ?? MediaIndexingService(
                mediaLibrary: mediaLibrary,
                indexStore: unavailableStore
            )
            self.dashboardProvider = dashboardProvider ?? DashboardService(indexStore: unavailableStore)
            self.bootstrapError = reason
        }
    }

    func onAppear() {
        guard currentTask == nil else {
            return
        }

        // Purge any Bin items that have passed their 30-day retention window
        Task { await BinService.shared.purgeExpiredItems() }

        currentTask = Task {
            await fastLaunchAndRefresh()
        }
    }

    func requestAccess() {
        currentTask?.cancel()
        currentTask = Task {
            await refreshIndex(requestAuthorizationIfNeeded: true)
        }
    }

    func cancelWork() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// Loads cached dashboard data immediately so the UI is displayed without delay,
    /// then performs background re-indexing.
    private func fastLaunchAndRefresh() async {
        if let bootstrapError {
            state = .failed(bootstrapError)
            currentTask = nil
            return
        }

        let status = await mediaLibrary.authorizationStatus()
        guard status.canReadLibrary else {
            if status == .notDetermined {
                state = .checkingAuthorization
            } else {
                state = .needsAuthorization(status)
            }
            await refreshIndex(requestAuthorizationIfNeeded: false)
            return
        }

        // 1. Try loading cached dashboard records first for instant display
        if let cachedDashboard = try? await dashboardProvider.makeSnapshot(isRefreshing: true),
           !cachedDashboard.records.isEmpty {
            state = .ready(status, cachedDashboard)
            // Trigger automatic background analysis immediately
            DuplicatePhotosSessionService.shared.analyzeIfNeeded(with: cachedDashboard.records)
            DuplicateVideosSessionService.shared.analyzeIfNeeded(with: cachedDashboard.records)
            SimilarPhotosSessionService.shared.analyzeIfNeeded(with: cachedDashboard.records)
        }

        // 2. Refresh index in background
        await refreshIndex(requestAuthorizationIfNeeded: false)
    }

    private func refreshIndex(requestAuthorizationIfNeeded: Bool) async {
        if let bootstrapError {
            state = .failed(bootstrapError)
            currentTask = nil
            return
        }

        var status = await mediaLibrary.authorizationStatus()
        if status == .notDetermined, requestAuthorizationIfNeeded {
            state = .checkingAuthorization
            status = await mediaLibrary.requestAuthorization()
        }

        guard status.canReadLibrary else {
            state = .needsAuthorization(status)
            currentTask = nil
            return
        }

        // Only show full-screen indexing if we don't already have a ready dashboard
        if case .ready = state {
            // Already showing dashboard; refresh silently in background
        } else {
            state = .indexing(status)
        }

        do {
            let snapshot = try await indexer.buildIndex()
            guard !Task.isCancelled else {
                return
            }

            let dashboard = await dashboardProvider.makeSnapshot(
                from: snapshot.records,
                isRefreshing: false
            )
            state = .ready(snapshot.authorizationStatus, dashboard)

            await MediaAnalysisCacheStore.shared.prune(
                toCurrentAssetIDs: Set(snapshot.records.map(\.id))
            )

            // Trigger automatic background duplicate analysis
            DuplicatePhotosSessionService.shared.analyzeIfNeeded(with: snapshot.records)
            DuplicateVideosSessionService.shared.analyzeIfNeeded(with: snapshot.records)
            SimilarPhotosSessionService.shared.analyzeIfNeeded(with: snapshot.records)
        } catch is CancellationError {
            if case .idle = state {
                state = .idle
            }
        } catch {
            if case .ready = state {
                // Keep showing existing dashboard if background refresh failed
            } else {
                state = .failed(error.localizedDescription)
            }
        }

        currentTask = nil
    }

    /// Silently re-indexes and updates the dashboard when library media or Bin items change.
    func refreshAfterLibraryChange() {
        Task {
            guard case .ready = state else { return }
            do {
                let snapshot = try await indexer.buildIndex()
                let dashboard = await dashboardProvider.makeSnapshot(
                    from: snapshot.records,
                    isRefreshing: false
                )
                state = .ready(snapshot.authorizationStatus, dashboard)

                await MediaAnalysisCacheStore.shared.prune(
                    toCurrentAssetIDs: Set(snapshot.records.map(\.id))
                )

                DuplicatePhotosSessionService.shared.analyzeIfNeeded(with: snapshot.records)
                DuplicateVideosSessionService.shared.analyzeIfNeeded(with: snapshot.records)
                SimilarPhotosSessionService.shared.analyzeIfNeeded(with: snapshot.records)
            } catch {
                // Preserve current UI if background refresh encounters an issue
            }
        }
    }
}
