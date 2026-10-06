import SwiftUI

/// A modern, media-first gallery cell inspired by native Apple Photos.
/// Emphasizes the media itself without bulky card containers or unnecessary margins.
struct MediaThumbnailCell: View {
    let item: MediaAssetIndexRecord
    var isSelected: Bool = false
    var showScreenshotBadge: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail container
            GeometryReader { geo in
                AssetThumbnailView(
                    assetId: item.id,
                    targetSize: CGSize(width: geo.size.width * 2, height: geo.size.height * 2)
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }

            // Dark gradient overlay at the bottom for metadata legibility
            if item.kind == .video || item.formattedFileSize != nil {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }

            // Bottom metadata overlay
            bottomOverlay
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: PhotoSenseTheme.cornerRadiusSmall, style: .continuous))
        // Selection state
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
        // Optional screenshot badge (only shown when explicitly enabled, hidden in Screenshots section)
        .overlay(alignment: .topLeading) {
            if showScreenshotBadge && item.isScreenshot {
                HStack(spacing: 3) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 8, weight: .bold))
                    Text("Screenshot")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.cyan.opacity(0.85))
                .clipShape(Capsule())
                .padding(6)
            }
        }
        .animation(PhotoSenseTheme.springQuick, value: isSelected)
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        if item.kind == .video {
            // Requirement 6: Resolution · Duration · Size (e.g. "1080p · 00:32 · 84.6 MB")
            let components: [String] = {
                var list: [String] = []
                if !item.resolutionString.isEmpty {
                    list.append(item.resolutionString)
                }
                list.append(item.formattedDuration)
                if let size = item.formattedFileSize {
                    list.append(size)
                }
                return list
            }()

            HStack(spacing: 3) {
                Image(systemName: "play.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.white.opacity(0.9))

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
        } else if let size = item.formattedFileSize {
            // Photo size pill
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
}
