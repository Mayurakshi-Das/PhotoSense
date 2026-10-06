import SwiftUI

struct BinView: View {
    @State private var viewModel = BinViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch viewModel.state {
                case .loading:
                    loadingView

                case .empty:
                    ConsistentEmptyStateView(
                        title: "Bin is Empty",
                        systemImage: "trash",
                        message: "Items you delete through PhotoSense appear here for 30 days before permanent removal.",
                        iconColor: .gray
                    )

                case .ready(let items):
                    contentView(items: items)

                case .failed(let message):
                    ConsistentEmptyStateView(
                        title: "Failed to Load",
                        systemImage: "exclamationmark.triangle",
                        message: message,
                        iconColor: .red
                    )
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Bin")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Delete Permanently?",
            isPresented: Binding(
                get: { viewModel.pendingPermanentDeleteItem != nil },
                set: { if !$0 { viewModel.cancelPermanentDelete() } }
            ),
            presenting: viewModel.pendingPermanentDeleteItem
        ) { _ in
            Button("Cancel", role: .cancel) {
                viewModel.cancelPermanentDelete()
            }
            Button("Delete Permanently", role: .destructive) {
                viewModel.confirmPermanentDelete()
            }
        } message: { item in
            Text("This \(item.kind.displayName) will be removed from the Bin. This action cannot be undone.")
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Loading Bin…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Content View

    private func contentView(items: [BinItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Summary header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(items.count) Items in Bin")
                        .font(.title3.bold())
                    Text("Auto-deleted after 30 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.formattedReclaimable)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text("Recoverable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusMedium, style: .continuous))
            .padding(.horizontal, 16)

            // Items list
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    BinItemRow(item: item) {
                        viewModel.requestPermanentDelete(item)
                    }

                    if index < items.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusMedium, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Bin Item Row

struct BinItemRow: View {
    let item: BinItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            BinItemThumbnailView(item: item)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.formattedFileSize)
                    .font(.body.weight(.semibold))

                HStack(spacing: 6) {
                    Text("Deleted \(item.deletedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(daysRemainingLabel(for: item))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(item.daysRemaining <= 3 ? .red : .secondary)
                }
            }

            Spacer()

            // Remove permanently button
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete Permanently")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func daysRemainingLabel(for item: BinItem) -> String {
        let days = item.daysRemaining
        if days == 0 { return "Expiring today" }
        if days == 1 { return "1 day left" }
        return "\(days) days left"
    }
}

// MARK: - Bin Thumbnail

private struct BinItemThumbnailView: View {
    let item: BinItem

    @State private var image: UIImage?
    @State private var hasFinishedLoading = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous)
                .fill(Color(.tertiarySystemFill))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if hasFinishedLoading {
                Image(systemName: item.kind == .video ? "video.fill" : "photo.fill")
                    .font(.body)
                    .foregroundStyle(item.kind == .video ? Color.indigo : Color.blue)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }

            if item.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous))
        .task(id: item.assetId) {
            hasFinishedLoading = false
            image = await ThumbnailPipeline.shared.thumbnail(
                for: item.assetId,
                targetSize: CGSize(width: 120, height: 120)
            )
            hasFinishedLoading = true
        }
    }
}

private extension BinAssetKind {
    var displayName: String {
        switch self {
        case .photo:
            "photo"
        case .video:
            "video"
        case .unknown:
            "item"
        }
    }
}
