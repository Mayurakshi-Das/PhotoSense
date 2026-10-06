import SwiftUI

struct DashboardCategoryCard: View {
    let summary: DashboardCategorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accentColor.opacity(0.14))

                    Image(systemName: summary.category.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 44, height: 44)

                Spacer()

                HStack(spacing: 4) {
                    stateBadge
                    if [.screenshots, .videos, .largeVideos, .duplicatePhotos, .duplicateVideos, .similarPhotos, .bin].contains(summary.category) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(summary.category.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(summary.category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayText)
                    .font(.title2.bold())
                    .monospacedDigit()

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accentColor)
                .frame(height: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator).opacity(0.24), lineWidth: 1)
        }
    }

    private var displayText: String {
        if summary.category == .duplicatePhotos || summary.category == .duplicateVideos || summary.category == .similarPhotos {
            switch summary.state {
            case .loading:
                return "Analyzing…"
            case .available(let count):
                return count.formatted()
            case .empty:
                return "0"
            case .notAnalyzed:
                return "Pending"
            case .failed:
                return "Issue"
            }
        }
        return summary.state.displayText
    }

    private var detailText: String {
        if summary.category == .duplicatePhotos {
            switch summary.state {
            case .loading:
                return "Finding duplicate photos…"
            case .available(let count):
                return count == 1 ? "1 duplicate group" : "\(count.formatted()) duplicate groups"
            case .empty:
                return "No duplicate photos"
            case .notAnalyzed:
                return "Not analyzed yet"
            case .failed(let message):
                return message
            }
        }
        if summary.category == .duplicateVideos {
            switch summary.state {
            case .loading:
                return "Finding duplicate videos…"
            case .available(let count):
                return count == 1 ? "1 duplicate group" : "\(count.formatted()) duplicate groups"
            case .empty:
                return "No duplicate videos"
            case .notAnalyzed:
                return "Not analyzed yet"
            case .failed(let message):
                return message
            }
        }
        if summary.category == .similarPhotos {
            switch summary.state {
            case .loading:
                return "Finding similar photos…"
            case .available(let count):
                return count == 1 ? "1 similar group" : "\(count.formatted()) similar groups"
            case .empty:
                return "No similar photos"
            case .notAnalyzed:
                return "Not analyzed yet"
            case .failed(let message):
                return message
            }
        }
        return summary.state.detailText
    }

    private var stateBadge: some View {
        Text(badgeText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(badgeColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var badgeText: String {
        if summary.category == .duplicatePhotos || summary.category == .duplicateVideos || summary.category == .similarPhotos {
            switch summary.state {
            case .loading:
                return "Analyzing"
            case .available, .empty:
                return "Ready"
            case .notAnalyzed:
                return "Pending"
            case .failed:
                return "Issue"
            }
        }
        return switch summary.state {
        case .loading:
            "Loading"
        case .available:
            "Ready"
        case .empty:
            "Empty"
        case .notAnalyzed:
            "Pending"
        case .failed:
            "Issue"
        }
    }

    private var badgeColor: Color {
        if summary.category == .duplicatePhotos || summary.category == .duplicateVideos || summary.category == .similarPhotos {
            switch summary.state {
            case .loading:
                return .blue
            case .available, .empty:
                return .green
            case .notAnalyzed:
                return .orange
            case .failed:
                return .red
            }
        }
        return switch summary.state {
        case .loading:
            .blue
        case .available:
            .green
        case .empty:
            .secondary
        case .notAnalyzed:
            .orange
        case .failed:
            .red
        }
    }

    private var accentColor: Color {
        switch summary.category {
        case .screenshots:
            .cyan
        case .videos:
            .indigo
        case .duplicatePhotos:
            .pink
        case .duplicateVideos:
            .red
        case .similarPhotos:
            .mint
        case .largeVideos:
            .orange
        case .bin:
            .gray
        }
    }
}
