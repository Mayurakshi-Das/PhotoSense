import Foundation
import Observation

@MainActor
@Observable
final class LargeVideosViewModel {
    enum State: Equatable {
        case loading
        case empty
        case ready(LargeVideoAnalysisResult)
        case failed(String)
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case top15 = "Largest 15%"
        case all = "All Videos"

        var id: String { rawValue }
    }

    var state: State = .loading
    var displayMode: DisplayMode = .top15

    // Selection state
    var selectedIDs: Set<String> = []
    var isSelecting: Bool = false
    var showDeleteConfirmation: Bool = false
    var showDeleteAlert: Bool = false
    var isDeletingItems: Bool = false
    var previewAssetId: String? = nil

    var deleteAlertTitle: String {
        let count = selectedCount
        return count == 1 ? "Want to delete 1 video?" : "Want to delete \(count) videos?"
    }

    @ObservationIgnored
    private let engine: any LargeVideoAnalyzing

    @ObservationIgnored
    private let mediaLibrary: any MediaLibraryProviding

    @ObservationIgnored
    private let binService: BinService

    @ObservationIgnored
    private var analysisTask: Task<Void, Never>?

    init(
        engine: any LargeVideoAnalyzing = LargeVideoAnalysisEngine(),
        mediaLibrary: any MediaLibraryProviding = PhotoKitMediaLibraryService(),
        binService: BinService = .shared
    ) {
        self.engine = engine
        self.mediaLibrary = mediaLibrary
        self.binService = binService
    }

    // MARK: - Analysis

    func startAnalysis(with records: [MediaAssetIndexRecord]) {
        analysisTask?.cancel()
        state = .loading
        selectedIDs = []
        isSelecting = false

        analysisTask = Task {
            do {
                let result = try await engine.analyzeVideos(from: records, mediaLibrary: mediaLibrary)
                guard !Task.isCancelled else { return }

                if result.allVideosSorted.isEmpty {
                    state = .empty
                } else {
                    state = .ready(result)
                }
            } catch is CancellationError {
                // Task was cleanly cancelled
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelWork() {
        analysisTask?.cancel()
        analysisTask = nil
    }

    // MARK: - Display mode

    func showAllVideos() {
        displayMode = .all
    }

    func showTop15Videos() {
        displayMode = .top15
    }

    // MARK: - Selection

    var selectedCount: Int { selectedIDs.count }

    func toggleSelection(for item: VideoAssetItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectAll() {
        guard case .ready(let result) = state else { return }
        let items: [VideoAssetItem] = displayMode == .top15
            ? result.top15PercentVideos
            : result.allVideosSorted
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

    // MARK: - Deletion

    /// Called after user confirms deletion. Moves items to the Bin and removes from PhotoKit.
    func deleteSelectedItems() {
        guard !selectedIDs.isEmpty else { return }
        deleteItems(withIDs: selectedIDs)
    }

    func deleteItemFromPreview(_ item: MediaAssetIndexRecord) {
        deleteItems(withIDs: [item.id], previewRecord: item)
    }

    private func deleteItems(
        withIDs ids: Set<String>,
        previewRecord: MediaAssetIndexRecord? = nil
    ) {
        guard !ids.isEmpty else { return }
        let idsToDelete = Array(ids)

        isDeletingItems = true

        Task {
            // Optimistically record items in the Bin before deletion
            if case .ready(let result) = state {
                let allItems = result.allVideosSorted
                let deletedItems = allItems.filter { idsToDelete.contains($0.id) }
                var binEntries: [BinEntry] = []
                for item in deletedItems {
                    binEntries.append(
                        await BinEntryFactory.make(
                            assetId: item.id,
                            kind: .video,
                            fileSize: item.fileSize
                        )
                    )
                }
                if let previewRecord, deletedItems.isEmpty {
                    binEntries.append(await BinEntryFactory.make(for: previewRecord))
                }
                await binService.addItems(binEntries)
            }

            do {
                try await mediaLibrary.deleteAssets(withIdentifiers: idsToDelete)

                // Deletion succeeded — update UI state to remove those items
                if case .ready(let result) = state {
                    let updated = result.removing(ids: Set(idsToDelete))
                    state = updated.allVideosSorted.isEmpty ? .empty : .ready(updated)
                }

                NotificationCenter.default.post(name: .mediaAssetsDidChange, object: nil)
            } catch MediaLibraryError.deletionCancelled {
                // User cancelled the system deletion sheet — roll back Bin entries
                await binService.removeItems(withIDs: Set(idsToDelete))
            } catch {
                // System or permission error — keep Bin entries as a record but don't update UI
                // (items may have been partially deleted on the Photos side)
            }

            selectedIDs = []
            isSelecting = false
            isDeletingItems = false
        }
    }
}
