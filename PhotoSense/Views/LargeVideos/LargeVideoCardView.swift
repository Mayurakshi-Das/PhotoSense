import SwiftUI

/// A clean, media-first video cell for Large Videos.
/// Displays ranking, video duration, resolution, and file size directly on the media.
struct LargeVideoCardView: View {
    let item: VideoAssetItem
    var isSelected: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail
            GeometryReader { geo in
                AssetThumbnailView(
                    assetId: item.id,
                    targetSize: CGSize(width: geo.size.width * 2, height: geo.size.height * 2)
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }

            // Dark gradient overlay at bottom for readability
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Bottom metadata pill: Resolution · Duration · Size
            HStack(spacing: 3) {
                Image(systemName: "play.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.white.opacity(0.9))

                let components = [
                    item.resolutionString.isEmpty ? nil : item.resolutionString,
                    item.formattedDuration,
                    item.formattedFileSize
                ].compactMap { $0 }

                Text(components.joined(separator: " · "))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(.ultraThinMaterial.opacity(0.85))
            .clipShape(Capsule())
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous))
        // Top-left rank badge
        .overlay(alignment: .topLeading) {
            Text("#\(item.rank)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(rankBadgeColor)
                .clipShape(Capsule())
                .padding(6)
        }
        // Top-right selection checkmark
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.blue)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous)
                    .stroke(Color.blue, lineWidth: 2.5)
            }
        }
        .animation(PhotoSenseTheme.springQuick, value: isSelected)
    }

    private var rankBadgeColor: Color {
        switch item.rank {
        case 1: .orange
        case 2: .indigo
        case 3: .teal
        default: Color.black.opacity(0.65)
        }
    }
}
