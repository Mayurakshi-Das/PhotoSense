import SwiftUI

struct AssetThumbnailView: View {
    let assetId: String
    let targetSize: CGSize
    var thumbnailPipeline: any ThumbnailPipelineProviding = ThumbnailPipeline.shared

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "video.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
            }
        }
        .task(id: assetId) {
            isLoading = true
            image = await thumbnailPipeline.thumbnail(for: assetId, targetSize: targetSize)
            isLoading = false
        }
    }
}
