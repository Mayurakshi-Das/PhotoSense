import SwiftUI

/// A clean, Apple-inspired navigation row connecting the Dashboard to individual media categories.
/// Provides a unified, media-first feel with category iconography, live status, and preview thumbnails.
struct CategoryNavigationRow: View {
    let category: DashboardCategory
    let title: String
    let subtitle: String
    let countText: String
    var statusBadge: String? = nil
    var previewAssetIds: [String] = []

    private var categoryColor: Color {
        PhotoSenseTheme.categoryColor(for: category)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Category Icon
            ZStack {
                RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous)
                    .fill(categoryColor.opacity(0.14))

                Image(systemName: category.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(categoryColor)
            }
            .frame(width: 38, height: 38)

            // Category Titles
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Optional Preview Thumbnails Stack (Media-first feel)
            if !previewAssetIds.isEmpty {
                HStack(spacing: -8) {
                    ForEach(Array(previewAssetIds.prefix(3).enumerated()), id: \.element) { index, id in
                        AssetThumbnailView(
                            assetId: id,
                            targetSize: CGSize(width: 48, height: 48)
                        )
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                        .zIndex(Double(3 - index))
                    }
                }
            }

            // Trailing Status / Count
            VStack(alignment: .trailing, spacing: 2) {
                if let status = statusBadge, !status.isEmpty {
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor(for: status))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(statusColor(for: status).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(countText)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .contentShape(Rectangle())
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Analyzing…", "Analyzing":
            .blue
        case "Ready":
            .green
        case "Issue":
            .red
        default:
            .secondary
        }
    }
}
