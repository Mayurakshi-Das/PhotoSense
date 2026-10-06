import SwiftUI

struct RootStatusView: View {
    let state: RootViewModel.State
    let requestAccess: () -> Void

    var body: some View {
        Group {
            switch state {
            case .idle, .loadingIndex, .checkingAuthorization:
                ProgressView("Checking Photos access...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()

            case .needsAuthorization(let status):
                AuthorizationStatusPanel(
                    status: status,
                    requestAccess: requestAccess
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

            case .indexing(let status):
                VStack(spacing: 12) {
                    ProgressView("Loading your library...")
                    Text(status.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

            case .ready(let status, let dashboard):
                DashboardView(authorizationStatus: status, snapshot: dashboard)

            case .failed(let message):
                ContentUnavailableView(
                    "Indexing Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
