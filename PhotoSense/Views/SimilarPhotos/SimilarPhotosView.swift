import SwiftUI

struct SimilarPhotosView: View {
    let records: [MediaAssetIndexRecord]

    @State private var viewModel = SimilarPhotosViewModel()

    // 3-column photo grid inside each group
    private let groupColumns = [
        GridItem(.flexible(), spacing: PhotoSenseTheme.gridSpacing),
        GridItem(.flexible(), spacing: PhotoSenseTheme.gridSpacing),
        GridItem(.flexible(), spacing: PhotoSenseTheme.gridSpacing)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch viewModel.state {
                case .notAnalyzed, .analyzing:
                    analyzingView

                case .empty:
                    ConsistentEmptyStateView(
                        title: "No Similar Photos",
                        systemImage: "checkmark.seal.fill",
                        message: "No visually similar photos were detected above the similarity threshold.",
                        iconColor: .mint
                    )

                case .ready(let result):
                    contentView(result: result)

                case .failed(let message):
                    ConsistentEmptyStateView(
                        title: "Analysis Failed",
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
        .navigationTitle("Similar Photos")
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
            if let selectedId = viewModel.previewAssetId, case .ready(let result) = viewModel.state {
                let allPhotos = result.groups.flatMap(\.photos)
                MediaGalleryPreviewView(
                    allItems: allPhotos,
                    initialAssetId: selectedId,
                    onDismiss: { viewModel.previewAssetId = nil },
                    onDelete: { item in
                        viewModel.deleteItemFromPreview(item)
                    }
                )
            }
        }
        .onAppear {
            viewModel.onViewAppear(with: records)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if viewModel.isSelecting {
                Menu {
                    Button("Select Similar (Keep Best)") {
                        viewModel.selectAllSecondary()
                    }
                    Button("Select All Photos") {
                        viewModel.selectAll()
                    }
                    Divider()
                    Button("Deselect All") {
                        viewModel.clearSelection()
                        viewModel.isSelecting = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }

                Button("Done") {
                    viewModel.clearSelection()
                }
                .fontWeight(.semibold)
            } else {
                Button {
                    viewModel.rescan(with: records)
                } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.state == .analyzing)

                if case .ready = viewModel.state {
                    Button("Select") {
                        viewModel.toggleSelectionMode()
                    }
                }
            }
        }
    }

    // MARK: - Bottom Action Bar for Deletion

    private var bottomActionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.selectedCount) photo\(viewModel.selectedCount == 1 ? "" : "s") selected")
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

    // MARK: - State Views

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 4) {
                Text("Analyzing Photos")
                    .font(.headline)
                Text("Finding similar shots using Vision neural embeddings…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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

    private func contentView(result: SimilarPhotoAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Summary header info
            summaryHeader(result: result)

            // Selection banner
            if viewModel.isSelecting {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.mint)
                    Text(viewModel.selectedCount == 0 ? "Tap photos to select" : "\(viewModel.selectedCount) selected")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.mint.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous))
                .padding(.horizontal, 16)
            }

            // Similar Groups List
            ForEach(result.groups) { group in
                similarGroupSection(group: group)
            }
        }
    }

    // MARK: - Summary Header
    private func summaryHeader(result: SimilarPhotoAnalysisResult) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(result.similarGroupCount) Similar Groups")
                    .font(.title3.bold())
                Text("\(result.secondaryPhotoCount) alternate shots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(result.formattedReclaimable)
                    .font(.title2.bold())
                    .foregroundStyle(PhotoSenseTheme.categoryColor(for: .similarPhotos))
                Text("Reclaimable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusMedium, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Similar Group Section
    private func similarGroupSection(group: SimilarPhotoGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(group.photos.count) shots", systemImage: "sparkles.rectangle.stack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(group.formattedAverageSimilarity)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PhotoSenseTheme.categoryColor(for: .similarPhotos))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(PhotoSenseTheme.categoryColor(for: .similarPhotos).opacity(0.12))
                    .clipShape(Capsule())

                Text(group.formattedTotalStorage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            LazyVGrid(columns: groupColumns, spacing: PhotoSenseTheme.gridSpacing) {
                ForEach(Array(group.photos.enumerated()), id: \.element.id) { index, record in
                    similarPhotoCell(record: record, isBest: index == 0)
                }
            }
            .padding(.horizontal, PhotoSenseTheme.gridSpacing)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func similarPhotoCell(record: MediaAssetIndexRecord, isBest: Bool) -> some View {
        let isSelected = viewModel.selectedIDs.contains(record.id)

        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                AssetThumbnailView(
                    assetId: record.id,
                    targetSize: CGSize(width: geo.size.width * 2, height: geo.size.height * 2)
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }

            // Dark gradient overlay
            if record.formattedFileSize != nil {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }

            // File size pill at bottom
            if let size = record.formattedFileSize {
                Text(size)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(.ultraThinMaterial.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous))
        // Top-left "Best" badge
        .overlay(alignment: .topLeading) {
            if isBest {
                Text("Best")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.mint.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(6)
            }
        }
        // Top-right selection checkmark
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.mint)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous)
                    .stroke(Color.mint, lineWidth: 2.5)
            }
        }
        .animation(PhotoSenseTheme.springQuick, value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isSelecting {
                withAnimation(PhotoSenseTheme.springQuick) {
                    viewModel.toggleSelection(for: record)
                }
            } else {
                viewModel.previewAssetId = record.id
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            if !viewModel.isSelecting {
                withAnimation(PhotoSenseTheme.springQuick) {
                    viewModel.isSelecting = true
                    viewModel.toggleSelection(for: record)
                }
            }
        }
    }
}
