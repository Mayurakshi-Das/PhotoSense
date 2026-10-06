import SwiftUI

struct DashboardMetricBadge: View {
    let title: String
    let value: Int
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value, format: .number)
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
