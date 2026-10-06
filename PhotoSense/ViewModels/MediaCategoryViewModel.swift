import Foundation
import Observation

@MainActor
@Observable
final class MediaCategoryViewModel {
    enum State: Equatable {
        case loading
        case empty
        case ready([MediaAssetIndexRecord])
        case failed(String)
    }

    var state: State = .loading
    var selectedIDs: Set<String> = []
    var isSelecting: Bool = false
    var showDeleteConfirmation: Bool = false
    var showDeleteAlert: Bool = false
    var isDeletingItems: Bool = false
    var previewAssetId: String? = nil

    let category: DashboardCategory

    @ObservationIgnored
    private let mediaLibrary: any MediaLibraryProviding
    @ObservationIgnored
    private let binService: BinService

    init(
        category: DashboardCategory,
        mediaLibrary: any MediaLibraryProviding = PhotoKitMediaLibraryService(),
        binService: BinService = .shared
    ) {
        self.category = category
        self.mediaLibrary = mediaLibrary
        self.binService = binService
    }

    func load(records: [MediaAssetIndexRecord]) {
        let filtered: [MediaAssetIndexRecord]
        switch category {
        case .screenshots:
            filtered = records
                .filter(\.isScreenshot)
                .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .videos:
            filtered = records
                .filter { $0.kind == .video }
                .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        default:
            filtered = records
        }

        if filtered.isEmpty {
            state = .empty
        } else {
            state = .ready(filtered)
        }
    }

    // MARK: - Selection

    var selectedCount: Int { selectedIDs.count }

    func toggleSelection(for item: MediaAssetIndexRecord) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectAll() {
        guard case .ready(let items) = state else { return }
        selectedIDs = Set(items.map(\.id))
    }

    func clearSelection() {
        selectedIDs = []
        isSelecting = false
    }

    func toggleSelectionMode() {
        isSelecting.toggle()
        if !isSelecting {
            selectedIDs = []
        }
    }

    // MARK: - Dialog Texts

    var deleteAlertTitle: String {
        let count = selectedCount
        switch category {
        case .screenshots:
            return count == 1 ? "Want to delete 1 screenshot?" : "Want to delete \(count) screenshots?"
        case .videos:
            return count == 1 ? "Want to delete 1 video?" : "Want to delete \(count) videos?"
        default:
            return count == 1 ? "Want to delete 1 item?" : "Want to delete \(count) items?"
        }
    }

    var deleteConfirmationTitle: String {
        let count = selectedCount
        switch category {
        case .screenshots:
            return count == 1 ? "Delete 1 screenshot?" : "Delete \(count) screenshots?"
        case .videos:
            return count == 1 ? "Delete 1 video?" : "Delete \(count) videos?"
        default:
            return count == 1 ? "Delete 1 item?" : "Delete \(count) items?"
        }
    }

    var deleteConfirmationMessage: String {
        switch category {
        case .screenshots:
            return "Deleted screenshots will be moved to the Bin and can be recovered for 30 days."
        case .videos:
            return "Deleted videos will be moved to the Bin and can be recovered for 30 days."
        default:
            return "Deleted items will be moved to the Bin and can be recovered for 30 days."
        }
    }

    // MARK: - Deletion

    func deleteSelectedItems() {
        guard !selectedIDs.isEmpty else { return }
        deleteItems(withIDs: selectedIDs)
    }

    func deleteItemFromPreview(_ item: MediaAssetIndexRecord) {
        deleteItems(withIDs: [item.id])
    }

    private func deleteItems(withIDs ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let idsToDelete = Array(ids)
        isDeletingItems = true

        Task {
            // Optimistically add to Bin before system deletion
            if case .ready(let items) = state {
                let deletedItems = items.filter { idsToDelete.contains($0.id) }
                var binEntries: [BinEntry] = []
                for item in deletedItems {
                    binEntries.append(await BinEntryFactory.make(for: item))
                }
                await binService.addItems(binEntries)
            }

            do {
                try await mediaLibrary.deleteAssets(withIdentifiers: idsToDelete)

                // Deletion confirmed by user in PhotoKit sheet
                if case .ready(let items) = state {
                    let remaining = items.filter { !idsToDelete.contains($0.id) }
                    state = remaining.isEmpty ? .empty : .ready(remaining)
                }

                // Notify root to re-index and refresh dashboard counts
                NotificationCenter.default.post(name: .mediaAssetsDidChange, object: nil)
            } catch MediaLibraryError.deletionCancelled {
                // User cancelled the system deletion sheet — rollback Bin entries
                await binService.removeItems(withIDs: Set(idsToDelete))
            } catch {
                // Other error — keep UI intact
            }

            selectedIDs = []
            isSelecting = false
            isDeletingItems = false
        }
    }
}
