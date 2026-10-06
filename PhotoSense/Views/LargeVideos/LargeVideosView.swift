import SwiftUI

struct LargeVideosView: View {
    let records: [MediaAssetIndexRecord]

    @State private var viewModel = LargeVideosViewModel()
    @State private var sizeFilter: LargeVideoSizeFilter = .all

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
                        title: "No Large Videos",
                        systemImage: "video.slash",
                        message: "Your library currently has no videos matching the large video criteria.",
                        iconColor: .orange
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
        .background(Color(.systemBackground))
        .navigationTitle("Large Videos")
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
            if let selectedId = viewModel.previewAssetId {
                MediaGalleryPreviewView(
                    allItems: records.filter { $0.kind == .video },
                    initialAssetId: selectedId,
                    onDismiss: { viewModel.previewAssetId = nil },
                    onDelete: { item in
                        viewModel.deleteItemFromPreview(item)
                    }
                )
            }
        }
        .onAppear {
            viewModel.startAnalysis(with: records)
        }
        .onDisappear {
            viewModel.cancelWork()
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
                Text("\(viewModel.selectedCount) video\(viewModel.selectedCount == 1 ? "" : "s") selected")
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
            Text("Analyzing video file sizes…")
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

    private func contentView(result: LargeVideoAnalysisResult) -> some View {
        let baseItems = viewModel.displayMode == .top15 ? result.top15PercentVideos : result.allVideosSorted
        let filteredItems = baseItems.filter { sizeFilter.matches(bytes: $0.fileSize) }

        return VStack(alignment: .leading, spacing: 14) {
            // Summary header info
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(result.allVideosSorted.count) Videos")
                            .font(.headline)
                        Text("Top 15% accounts for \(result.top15FormattedStorage)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(result.totalFormattedStorage)
                            .font(.headline.bold())
                            .foregroundStyle(.orange)
                        Text("Total Video Space")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)

                // Display Mode Segmented Control
                Picker("Display", selection: $viewModel.displayMode) {
                    Text("Top 15% (\(result.top15PercentVideos.count))").tag(LargeVideosViewModel.DisplayMode.top15)
                    Text("All Videos (\(result.allVideosSorted.count))").tag(LargeVideosViewModel.DisplayMode.all)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                // Size Filter Bar (Requirement 7)
                SizeFilterBar(options: LargeVideoSizeFilter.allCases, selected: $sizeFilter)
                    .padding(.horizontal, 14)
            }

            // Selection Banner
            if viewModel.isSelecting {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                    Text(viewModel.selectedCount == 0 ? "Tap videos to select" : "\(viewModel.selectedCount) selected")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous))
                .padding(.horizontal, 14)
            }

            // Media Grid
            if filteredItems.isEmpty {
                ConsistentEmptyStateView(
                    title: "No Videos Match Filter",
                    systemImage: "line.3.horizontal.decrease.circle",
                    message: "No videos found matching '\(sizeFilter.description)'.",
                    iconColor: .secondary
                )
            } else {
                LazyVGrid(columns: columns, spacing: PhotoSenseTheme.gridSpacing) {
                    ForEach(filteredItems) { item in
                        videoCard(for: item)
                    }
                }
                .padding(.horizontal, PhotoSenseTheme.gridSpacing)
            }
        }
    }

    @ViewBuilder
    private func videoCard(for item: VideoAssetItem) -> some View {
        let isSelected = viewModel.selectedIDs.contains(item.id)

        LargeVideoCardView(item: item, isSelected: isSelected)
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
