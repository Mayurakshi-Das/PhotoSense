import SwiftUI

struct DashboardView: View {
    let authorizationStatus: MediaLibraryAuthorizationStatus
    let snapshot: DashboardSnapshot

    private let navigableCategories: Set<DashboardCategory> = [
        .screenshots, .videos, .largeVideos,
        .duplicatePhotos, .duplicateVideos, .similarPhotos,
        .bin
    ]

    private var duplicateSession = DuplicatePhotosSessionService.shared
    private var duplicateVideosSession = DuplicateVideosSessionService.shared
    private var similarPhotosSession = SimilarPhotosSessionService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // MARK: - 1. Minimal Elegant Header
                header

                // MARK: - 2. Single Visual Library Storage Overview
                storageOverview

                // MARK: - 3. Clean Up Recommendations
                cleanupSection

                // MARK: - 4. Media Library Sections
                mediaSection

                // MARK: - 5. Utilities (Bin)
                utilitiesSection
            }
            .padding(.horizontal, PhotoSenseTheme.contentPadding)
            .padding(.top, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Keep navigation bar clean since large custom title is displayed in header
                EmptyView()
            }
        }
        .navigationDestination(for: DashboardCategory.self) { category in
            switch category {
            case .screenshots:
                ScreenshotsView(records: snapshot.records)
            case .videos:
                VideosView(records: snapshot.records)
            case .largeVideos:
                LargeVideosView(records: snapshot.records)
            case .duplicatePhotos:
                DuplicatePhotosView(records: snapshot.records)
            case .duplicateVideos:
                DuplicateVideosView(records: snapshot.records)
            case .similarPhotos:
                SimilarPhotosView(records: snapshot.records)
            case .bin:
                BinView()
            }
        }
        .onAppear {
            duplicateSession.analyzeIfNeeded(with: snapshot.records)
            duplicateVideosSession.analyzeIfNeeded(with: snapshot.records)
            similarPhotosSession.analyzeIfNeeded(with: snapshot.records)
        }
    }

    // MARK: - Header (Minimal & Elegant Branding)
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text("PhotoSense")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if snapshot.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let lastIndexedAt = snapshot.lastIndexedAt {
                Text("Last indexed \(lastIndexedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if snapshot.isRefreshing {
                Text("Indexing library…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Single Visual Storage Overview
    private var storageOverview: some View {
        let isAnalyzing = duplicateSession.state == .analyzing ||
                          duplicateVideosSession.state == .analyzing ||
                          similarPhotosSession.state == .analyzing

        let segments: [LibraryCategorySegment] = [
            LibraryCategorySegment(
                category: .screenshots,
                count: snapshot.indexSummary.screenshots,
                color: PhotoSenseTheme.categoryColor(for: .screenshots)
            ),
            LibraryCategorySegment(
                category: .videos,
                count: snapshot.indexSummary.videos,
                color: PhotoSenseTheme.categoryColor(for: .videos)
            ),
            LibraryCategorySegment(
                category: .duplicatePhotos,
                count: duplicatePhotoCount,
                color: PhotoSenseTheme.categoryColor(for: .duplicatePhotos)
            ),
            LibraryCategorySegment(
                category: .duplicateVideos,
                count: duplicateVideoCount,
                color: PhotoSenseTheme.categoryColor(for: .duplicateVideos)
            ),
            LibraryCategorySegment(
                category: .similarPhotos,
                count: similarPhotoCount,
                color: PhotoSenseTheme.categoryColor(for: .similarPhotos)
            ),
            LibraryCategorySegment(
                category: .largeVideos,
                count: largeVideoCount,
                color: PhotoSenseTheme.categoryColor(for: .largeVideos)
            )
        ]

        return LibraryStorageBarView(
            totalAssets: snapshot.indexSummary.totalAssets,
            segments: segments,
            totalCleanableBytes: totalCleanableBytes,
            isAnalyzing: isAnalyzing
        )
    }

    // MARK: - Clean Up Recommendations Section
    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLEAN UP")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // Duplicate Photos
                NavigationLink(value: DashboardCategory.duplicatePhotos) {
                    CategoryNavigationRow(
                        category: .duplicatePhotos,
                        title: "Duplicate Photos",
                        subtitle: duplicatePhotosSubtitle,
                        countText: duplicatePhotosCountText,
                        statusBadge: duplicatePhotosStatusBadge,
                        previewAssetIds: duplicatePhotoPreviewIds
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 64)

                // Duplicate Videos
                NavigationLink(value: DashboardCategory.duplicateVideos) {
                    CategoryNavigationRow(
                        category: .duplicateVideos,
                        title: "Duplicate Videos",
                        subtitle: duplicateVideosSubtitle,
                        countText: duplicateVideosCountText,
                        statusBadge: duplicateVideosStatusBadge,
                        previewAssetIds: duplicateVideoPreviewIds
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 64)

                // Similar Photos
                NavigationLink(value: DashboardCategory.similarPhotos) {
                    CategoryNavigationRow(
                        category: .similarPhotos,
                        title: "Similar Photos",
                        subtitle: similarPhotosSubtitle,
                        countText: similarPhotosCountText,
                        statusBadge: similarPhotosStatusBadge,
                        previewAssetIds: similarPhotoPreviewIds
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 64)

                // Large Videos
                NavigationLink(value: DashboardCategory.largeVideos) {
                    CategoryNavigationRow(
                        category: .largeVideos,
                        title: "Large Videos",
                        subtitle: "High storage consumption",
                        countText: "\(snapshot.indexSummary.videos.formatted())",
                        statusBadge: nil,
                        previewAssetIds: videoPreviewIds
                    )
                }
                .buttonStyle(.plain)
            }
            .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusMedium, style: .continuous))
        }
    }

    // MARK: - Media Library Section
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEDIA")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // Screenshots
                NavigationLink(value: DashboardCategory.screenshots) {
                    CategoryNavigationRow(
                        category: .screenshots,
                        title: "Screenshots",
                        subtitle: "Indexed screenshots",
                        countText: "\(snapshot.indexSummary.screenshots.formatted())",
                        statusBadge: nil,
                        previewAssetIds: screenshotPreviewIds
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 64)

                // Videos
                NavigationLink(value: DashboardCategory.videos) {
                    CategoryNavigationRow(
                        category: .videos,
                        title: "Videos",
                        subtitle: "All library videos",
                        countText: "\(snapshot.indexSummary.videos.formatted())",
                        statusBadge: nil,
                        previewAssetIds: videoPreviewIds
                    )
                }
                .buttonStyle(.plain)
            }
            .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusMedium, style: .continuous))
        }
    }

    // MARK: - Utilities Section
    private var utilitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UTILITIES")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 4)

            NavigationLink(value: DashboardCategory.bin) {
                CategoryNavigationRow(
                    category: .bin,
                    title: "Bin",
                    subtitle: "Recently deleted in PhotoSense",
                    countText: binItemCountText,
                    statusBadge: nil
                )
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusMedium, style: .continuous))
        }
    }

    // MARK: - Computed Counts and Reclaimable Storage

    private var totalCleanableBytes: Int64 {
        var total: Int64 = 0
        if case .ready(let result) = duplicateSession.state {
            total += result.totalReclaimableBytes
        }
        if case .ready(let result) = duplicateVideosSession.state {
            total += result.totalReclaimableBytes
        }
        if case .ready(let result) = similarPhotosSession.state {
            total += result.totalReclaimableBytes
        }
        return total
    }

    private var duplicatePhotoCount: Int {
        if case .ready(let result) = duplicateSession.state {
            return result.groups.flatMap(\.photos).count
        }
        return 0
    }

    private var duplicateVideoCount: Int {
        if case .ready(let result) = duplicateVideosSession.state {
            return result.groups.flatMap(\.videos).count
        }
        return 0
    }

    private var similarPhotoCount: Int {
        if case .ready(let result) = similarPhotosSession.state {
            return result.groups.flatMap(\.photos).count
        }
        return 0
    }

    private var largeVideoCount: Int {
        snapshot.indexSummary.videos
    }

    // MARK: - Category Row Helpers

    private var duplicatePhotosSubtitle: String {
        switch duplicateSession.state {
        case .analyzing:
            "Finding duplicates…"
        case .ready(let result):
            if result.groups.isEmpty {
                "No duplicate photos found"
            } else {
                "\(result.formattedReclaimable) cleanable"
            }
        case .empty:
            "No duplicate photos"
        case .notAnalyzed:
            "Ready to analyze"
        case .failed(let message):
            message
        }
    }

    private var duplicatePhotosCountText: String {
        switch duplicateSession.state {
        case .ready(let result):
            result.groups.isEmpty ? "0" : "\(result.groups.count) groups"
        case .analyzing:
            "…"
        default:
            "0"
        }
    }

    private var duplicatePhotosStatusBadge: String? {
        switch duplicateSession.state {
        case .analyzing: "Analyzing…"
        case .ready: "Ready"
        case .failed: "Issue"
        default: nil
        }
    }

    private var duplicateVideosSubtitle: String {
        switch duplicateVideosSession.state {
        case .analyzing:
            "Finding duplicates…"
        case .ready(let result):
            if result.groups.isEmpty {
                "No duplicate videos found"
            } else {
                "\(result.formattedReclaimable) cleanable"
            }
        case .empty:
            "No duplicate videos"
        case .notAnalyzed:
            "Ready to analyze"
        case .failed(let message):
            message
        }
    }

    private var duplicateVideosCountText: String {
        switch duplicateVideosSession.state {
        case .ready(let result):
            result.groups.isEmpty ? "0" : "\(result.groups.count) groups"
        case .analyzing:
            "…"
        default:
            "0"
        }
    }

    private var duplicateVideosStatusBadge: String? {
        switch duplicateVideosSession.state {
        case .analyzing: "Analyzing…"
        case .ready: "Ready"
        case .failed: "Issue"
        default: nil
        }
    }

    private var similarPhotosSubtitle: String {
        switch similarPhotosSession.state {
        case .analyzing:
            "Finding similar shots…"
        case .ready(let result):
            if result.groups.isEmpty {
                "No similar photos found"
            } else {
                "\(result.formattedReclaimable) cleanable"
            }
        case .empty:
            "No similar photos"
        case .notAnalyzed:
            "Ready to analyze"
        case .failed(let message):
            message
        }
    }

    private var similarPhotosCountText: String {
        switch similarPhotosSession.state {
        case .ready(let result):
            result.groups.isEmpty ? "0" : "\(result.groups.count) groups"
        case .analyzing:
            "…"
        default:
            "0"
        }
    }

    private var similarPhotosStatusBadge: String? {
        switch similarPhotosSession.state {
        case .analyzing: "Analyzing…"
        case .ready: "Ready"
        case .failed: "Issue"
        default: nil
        }
    }

    private var binItemCountText: String {
        if let binSummary = snapshot.categories.first(where: { $0.category == .bin }) {
            if case .available(let count) = binSummary.state {
                return "\(count.formatted())"
            }
        }
        return "0"
    }

    // MARK: - Preview Thumbnail Assets

    private var screenshotPreviewIds: [String] {
        Array(snapshot.records.filter(\.isScreenshot).prefix(3).map(\.id))
    }

    private var videoPreviewIds: [String] {
        Array(snapshot.records.filter { $0.kind == .video }.prefix(3).map(\.id))
    }

    private var duplicatePhotoPreviewIds: [String] {
        if case .ready(let result) = duplicateSession.state {
            return Array(result.groups.flatMap(\.photos).prefix(3).map(\.id))
        }
        return []
    }

    private var duplicateVideoPreviewIds: [String] {
        if case .ready(let result) = duplicateVideosSession.state {
            return Array(result.groups.flatMap(\.videos).prefix(3).map(\.id))
        }
        return []
    }

    private var similarPhotoPreviewIds: [String] {
        if case .ready(let result) = similarPhotosSession.state {
            return Array(result.groups.flatMap(\.photos).prefix(3).map(\.id))
        }
        return []
    }
}
