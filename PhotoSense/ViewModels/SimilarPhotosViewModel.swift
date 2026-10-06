import Foundation
import Observation

@MainActor
@Observable
final class SimilarPhotosViewModel {
    typealias State = SimilarPhotosSessionService.State

    var selectedIDs: Set<String> = []
    var isSelecting: Bool = false
    var showDeleteAlert: Bool = false
    var isDeletingItems: Bool = false
    var previewAssetId: String? = nil

    @ObservationIgnored private let session: SimilarPhotosSessionService
    @ObservationIgnored private let binService: BinService
    @ObservationIgnored private let mediaLibrary: any MediaLibraryProviding

    var state: State {
        session.state
    }

    init(
        session: SimilarPhotosSessionService = .shared,
        binService: BinService = .shared,
        mediaLibrary: any MediaLibraryProviding = PhotoKitMediaLibraryService()
    ) {
        self.session = session
        self.binService = binService
        self.mediaLibrary = mediaLibrary
    }

    // MARK: - Lifecycle

    /// Reuses any existing session result immediately — no re-analysis unless state is unresolved.
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

    /// Selects all secondary (non-representative) photos in every group.
    func selectAllSecondary() {
        guard case .ready(let result) = state else { return }
        selectedIDs = Set(result.groups.flatMap(\.secondaryPhotos).map(\.id))
    }

    /// Selects every photo in every similar group.
    func selectAll() {
        guard case .ready(let result) = state else { return }
        selectedIDs = Set(result.groups.flatMap(\.photos).map(\.id))
    }

    func clearSelection() {
        selectedIDs = []
        isSelecting = false
    }

    func toggleSelectionMode() {
        isSelecting.toggle()
        if !isSelecting { selectedIDs = [] }
    }

    // MARK: - Delete dialog

    var deleteAlertTitle: String {
        let count = selectedCount
        return count == 1 ? "Want to delete 1 photo?" : "Want to delete \(count) photos?"
    }

    // MARK: - Deletion

    func deleteSelectedItems() {
        guard case .ready(let result) = state, !selectedIDs.isEmpty else { return }
        deleteItems(withIDs: selectedIDs, from: result.groups.flatMap(\.photos))
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
            let deletedRecords = records.filter { idsToDelete.contains($0.id) }
            let binEntries = deletedRecords.map {
                BinEntry(assetId: $0.id, kind: .photo, fileSize: $0.fileSize ?? 0)
            }
            await binService.addItems(binEntries)

            do {
                try await mediaLibrary.deleteAssets(withIdentifiers: idsToDelete)

                // Surgically update session state without reanalysis
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
