import SwiftUI

struct SummaryMetricView: View {
    let title: String
    let value: Int
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(value, format: .number)
                    .font(.title3.bold())
                    .monospacedDigit()

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
