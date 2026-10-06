import SwiftUI

struct ScreenshotsView: View {
    let records: [MediaAssetIndexRecord]

    @State private var viewModel = MediaCategoryViewModel(category: .screenshots)

    // Native iPhone Photos-style 3-column media grid
    private let columns = [
        GridItem(.flexible(), spacing: PhotoSenseTheme.gridSpacing),
        GridItem(.flexible(), spacing: PhotoSenseTheme.gridSpacing),
        GridItem(.flexible(), spacing: PhotoSenseTheme.gridSpacing)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch viewModel.state {
                case .loading:
                    loadingView

                case .empty:
                    ConsistentEmptyStateView(
                        title: "No Screenshots",
                        systemImage: "camera.viewfinder",
                        message: "No screenshots were detected in your indexed library.",
                        iconColor: .cyan
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
        .background(Color(.systemBackground))
        .navigationTitle("Screenshots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert(
            viewModel.deleteAlertTitle,
            isPresented: $viewModel.showDeleteAlert
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteSelectedItems()
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isSelecting && viewModel.selectedCount > 0 {
                bottomActionBar
            }
        }
        .overlay {
            if viewModel.isDeletingItems {
                deletingOverlay
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.previewAssetId != nil },
            set: { if !$0 { viewModel.previewAssetId = nil } }
        )) {
            if let selectedId = viewModel.previewAssetId, case .ready(let items) = viewModel.state {
                MediaGalleryPreviewView(
                    allItems: items,
                    initialAssetId: selectedId,
                    onDismiss: { viewModel.previewAssetId = nil },
                    onDelete: { item in
                        viewModel.deleteItemFromPreview(item)
                    }
                )
            }
        }
        .onAppear {
            viewModel.load(records: records)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if viewModel.isSelecting {
                Button(viewModel.selectedCount > 0 ? "Deselect All" : "Select All") {
                    if viewModel.selectedCount > 0 {
                        viewModel.clearSelection()
                        viewModel.isSelecting = true
                    } else {
                        viewModel.selectAll()
                    }
                }
                .font(.subheadline)

                Button("Done") {
                    viewModel.clearSelection()
                }
                .fontWeight(.semibold)
            } else {
                Button("Select") {
                    viewModel.toggleSelectionMode()
                }
                .disabled(viewModel.state == .empty)
            }
        }
    }

    // MARK: - Bottom Action Bar for Deletion

    private var bottomActionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.selectedCount) screenshot\(viewModel.selectedCount == 1 ? "" : "s") selected")
                    .font(.subheadline.bold())
                Text("Move to Bin")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                viewModel.showDeleteAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("Delete")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.red)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusLarge, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Loading screenshots…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var deletingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Deleting…").font(.headline).foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Content View

    private func contentView(items: [MediaAssetIndexRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary header line
            HStack {
                Text("\(items.count) Screenshots")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 16)

            // Selection Banner
            if viewModel.isSelecting {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                    Text(viewModel.selectedCount == 0 ? "Tap screenshots to select" : "\(viewModel.selectedCount) selected")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous))
                .padding(.horizontal, 14)
            }

            // Media Grid (Requirement 8: Clean thumbnails with NO 'Screenshot' badge)
            LazyVGrid(columns: columns, spacing: PhotoSenseTheme.gridSpacing) {
                ForEach(items) { item in
                    screenshotCell(for: item)
                }
            }
            .padding(.horizontal, PhotoSenseTheme.gridSpacing)
        }
    }

    @ViewBuilder
    private func screenshotCell(for item: MediaAssetIndexRecord) -> some View {
        let isSelected = viewModel.selectedIDs.contains(item.id)

        // showScreenshotBadge is FALSE per user requirement 8
        MediaThumbnailCell(
            item: item,
            isSelected: isSelected,
            showScreenshotBadge: false
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isSelecting {
                withAnimation(PhotoSenseTheme.springQuick) {
                    viewModel.toggleSelection(for: item)
                }
            } else {
                viewModel.previewAssetId = item.id
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            if !viewModel.isSelecting {
                withAnimation(PhotoSenseTheme.springQuick) {
                    viewModel.isSelecting = true
                    viewModel.toggleSelection(for: item)
                }
            }
        }
    }
}
