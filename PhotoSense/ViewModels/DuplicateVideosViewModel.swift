import Foundation
import Observation

@MainActor
@Observable
final class DuplicateVideosViewModel {
    typealias State = DuplicateVideosSessionService.State

    var selectedIDs: Set<String> = []
    var isSelecting: Bool = false
    var showDeleteAlert: Bool = false
    var isDeletingItems: Bool = false
    var previewAssetId: String? = nil

    @ObservationIgnored private let session: DuplicateVideosSessionService
    @ObservationIgnored private let binService: BinService
    @ObservationIgnored private let mediaLibrary: any MediaLibraryProviding

    var state: State {
        session.state
    }

    init(
        session: DuplicateVideosSessionService = .shared,
        binService: BinService = .shared,
        mediaLibrary: any MediaLibraryProviding = PhotoKitMediaLibraryService()
    ) {
        self.session = session
        self.binService = binService
        self.mediaLibrary = mediaLibrary
    }

    // MARK: - Lifecycle

    /// Checks if a completed session result already exists:
    /// - If yes → reuses it immediately (no analysis or video decoding).
    /// - If no → starts analysis.
    func onViewAppear(with records: [MediaAssetIndexRecord]) {
        session.analyzeIfNeeded(with: records)
    }

    /// User-triggered manual re-scan.
    func rescan(with records: [MediaAssetIndexRecord]) {
        clearSelection()
        session.forceAnalyze(with: records)
    }

    // MARK: - Selection

    var selectedCount: Int { selectedIDs.count }

    func toggleSelection(for record: MediaAssetIndexRecord) {
        if selectedIDs.contains(record.id) {
            selectedIDs.remove(record.id)
        } else {
            selectedIDs.insert(record.id)
        }
    }

    /// Selects all deletion candidates (all videos except the representative of each group).
    func selectAllCandidates() {
        guard case .ready(let result) = state else { return }
        selectedIDs = Set(result.groups.flatMap(\.deletionCandidates).map(\.id))
    }

    /// Selects every video in every group (including representatives).
    func selectAll() {
        guard case .ready(let result) = state else { return }
        selectedIDs = Set(result.groups.flatMap(\.videos).map(\.id))
    }

    func clearSelection() {
        selectedIDs = []
        isSelecting = false
    }

    func toggleSelectionMode() {
        isSelecting.toggle()
        if !isSelecting { selectedIDs = [] }
    }

    // MARK: - Deletion dialog text

    var deleteAlertTitle: String {
        let count = selectedCount
        return count == 1 ? "Want to delete 1 video?" : "Want to delete \(count) videos?"
    }

    // MARK: - Deletion

    func deleteSelectedItems() {
        guard case .ready(let result) = state, !selectedIDs.isEmpty else { return }
        deleteItems(withIDs: selectedIDs, from: result.groups.flatMap(\.videos))
    }

    func deleteItemFromPreview(_ item: MediaAssetIndexRecord) {
        deleteItems(withIDs: [item.id], from: [item])
    }

    private func deleteItems(
        withIDs ids: Set<String>,
        from records: [MediaAssetIndexRecord]
    ) {
        guard !ids.isEmpty else { return }
        let idsToDelete = Array(ids)
        isDeletingItems = true

        Task {
            // Collect records for Bin entries
            let deletedRecords = records.filter { idsToDelete.contains($0.id) }
            var binEntries: [BinEntry] = []
            for record in deletedRecords {
                binEntries.append(await BinEntryFactory.make(for: record))
            }
            await binService.addItems(binEntries)

            do {
                try await mediaLibrary.deleteAssets(withIdentifiers: idsToDelete)

                // Update session state in-memory
                session.removeDeletedAssets(ids: Set(idsToDelete))

                NotificationCenter.default.post(name: .mediaAssetsDidChange, object: nil)
            } catch MediaLibraryError.deletionCancelled {
                await binService.removeItems(withIDs: Set(idsToDelete))
            } catch {
                // Preserve UI on other errors
            }

            selectedIDs = []
            isSelecting = false
            isDeletingItems = false
        }
    }
}
