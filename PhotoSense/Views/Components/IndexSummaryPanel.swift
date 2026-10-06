import SwiftUI

struct IndexSummaryPanel: View {
    let status: MediaLibraryAuthorizationStatus
    let summary: MediaIndexSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Media Index Ready")
                    .font(.title2.bold())

                Text(status.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                SummaryMetricView(title: "Assets", value: summary.totalAssets, symbol: "photo.on.rectangle")
                SummaryMetricView(title: "Photos", value: summary.photos, symbol: "photo")
                SummaryMetricView(title: "Videos", value: summary.videos, symbol: "video")
                SummaryMetricView(title: "Screenshots", value: summary.screenshots, symbol: "camera.viewfinder")
                SummaryMetricView(title: "Failures", value: summary.failures, symbol: "exclamationmark.triangle")
            }
        }
        .padding(20)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }
}
