import SwiftUI

struct AuthorizationStatusPanel: View {
    let status: MediaLibraryAuthorizationStatus
    let requestAccess: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(iconColor)

            VStack(spacing: 8) {
                Text(status.title)
                    .font(.title3.bold())

                Text(status.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if status == .notDetermined {
                Button(action: requestAccess) {
                    Label("Allow Photos Access", systemImage: "photo.stack")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var iconName: String {
        switch status {
        case .notDetermined:
            "photo.badge.plus"
        case .authorized, .limited:
            "checkmark.circle"
        case .denied, .restricted, .unknown:
            "lock.circle"
        }
    }

    private var iconColor: Color {
        switch status {
        case .notDetermined:
            .accentColor
        case .authorized, .limited:
            .green
        case .denied, .restricted, .unknown:
            .red
        }
    }
}
