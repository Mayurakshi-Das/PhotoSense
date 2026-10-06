import SwiftUI

/// A clean, Apple-inspired empty state component used consistently throughout PhotoSense.
/// Avoids oversized illustrations and provides clear, reassuring status messages.
struct ConsistentEmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String
    var iconColor: Color = .secondary

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.vertical, 32)
    }
}

#Preview {
    ConsistentEmptyStateView(
        title: "No Duplicate Photos",
        systemImage: "checkmark.seal.fill",
        message: "No exact duplicate photos were detected in your indexed library.",
        iconColor: .green
    )
}
