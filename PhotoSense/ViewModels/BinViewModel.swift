import Foundation
import Observation

@MainActor
@Observable
final class BinViewModel {
    enum State {
        case loading
        case empty
        case ready([BinItem])
        case failed(String)
    }

    var state: State = .loading
    var totalReclaimable: Int64 = 0
    var pendingPermanentDeleteItem: BinItem?

    @ObservationIgnored
    private let binService: BinService

    init(binService: BinService = .shared) {
        self.binService = binService
    }

    func load() {
        Task {
            do {
                await binService.purgeExpiredItems()
                let items = try await binService.fetchActiveItems()
                let reclaimable = await binService.totalReclaimableBytes()
                totalReclaimable = reclaimable
                if items.isEmpty {
                    state = .empty
                } else {
                    state = .ready(items)
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func requestPermanentDelete(_ item: BinItem) {
        pendingPermanentDeleteItem = item
    }

    func cancelPermanentDelete() {
        pendingPermanentDeleteItem = nil
    }

    func confirmPermanentDelete() {
        guard let item = pendingPermanentDeleteItem else { return }
        pendingPermanentDeleteItem = nil
        removeFromBin(item)
    }

    private func removeFromBin(_ item: BinItem) {
        Task {
            await binService.removeItems(withIDs: [item.assetId])
            load()
            NotificationCenter.default.post(name: .mediaAssetsDidChange, object: nil)
        }
    }

    var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalReclaimable, countStyle: .file)
    }
}
