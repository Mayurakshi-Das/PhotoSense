import SwiftUI

/// Item representing a segment in the library storage overview.
struct LibraryCategorySegment: Identifiable {
    let category: DashboardCategory
    let count: Int
    let color: Color

    var id: String { category.id }
}

/// A visual media library storage overview that replaces the previous 3-metric cards.
/// Displays:
/// 1. Prominent "Total cleanable" figure
/// 2. Segmented horizontal bar representing TOTAL ASSETS across the 6 tracked categories
/// 3. Clean legend with color indicators, category names, and counts outside the bar.
struct LibraryStorageBarView: View {
    let totalAssets: Int
    let segments: [LibraryCategorySegment]
    let totalCleanableBytes: Int64
    var isAnalyzing: Bool = false

    private var formattedCleanable: String {
        if totalCleanableBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: totalCleanableBytes, countStyle: .file)
        } else if isAnalyzing {
            return "Calculating…"
        } else {
            return "0 B"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // MARK: - Prominent Cleanable Storage Header
            cleanableHeader

            // MARK: - Total Assets & Segmented Progress Bar
            progressBarSection

            // MARK: - Clean Legend
            legendGrid
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusLarge, style: .continuous))
    }

    // MARK: - Total Cleanable Prominent Section
    private var cleanableHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total cleanable")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formattedCleanable)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(totalCleanableBytes > 0 ? PhotoSenseTheme.reclaimableAccent : .primary)

                    if totalCleanableBytes > 0 {
                        Text("reclaimable space")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isAnalyzing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Progress Bar
    private var progressBarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TOTAL ASSETS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()

                Text("\(totalAssets.formatted()) items")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Clean segmented bar without any numbers inside
            GeometryReader { geo in
                let totalCount = max(segments.map(\.count).reduce(0, +), 1)
                let activeSegments = segments.filter { $0.count > 0 }

                HStack(spacing: 2) {
                    if activeSegments.isEmpty {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(activeSegments) { segment in
                            let ratio = max(CGFloat(segment.count) / CGFloat(totalCount), 0.02)
                            let segmentWidth = max(geo.size.width * ratio - 2, 4)

                            segment.color
                                .frame(width: segmentWidth)
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
        }
    }

    // MARK: - Legend Grid
    private var legendGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                HStack(spacing: 8) {
                    Circle()
                        .fill(segment.color)
                        .frame(width: 8, height: 8)

                    Text(segment.category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(segment.count.formatted())
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.top, 4)
    }
}
