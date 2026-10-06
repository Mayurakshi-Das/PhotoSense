import SwiftUI

/// Compatibility wrapper forwarding to modern `MediaThumbnailCell`.
struct MediaAssetCardView: View {
    let item: MediaAssetIndexRecord
    var isSelected: Bool = false
    var showScreenshotBadge: Bool = false

    var body: some View {
        MediaThumbnailCell(
            item: item,
            isSelected: isSelected,
            showScreenshotBadge: showScreenshotBadge
        )
    }
}
