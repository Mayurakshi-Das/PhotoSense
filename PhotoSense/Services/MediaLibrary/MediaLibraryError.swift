import Foundation

enum MediaLibraryError: LocalizedError, Sendable {
    case accessUnavailable(MediaLibraryAuthorizationStatus)
    case assetFetchFailed(String)
    case deletionCancelled

    var errorDescription: String? {
        switch self {
        case .accessUnavailable(let status):
            status.message
        case .assetFetchFailed(let reason):
            "Unable to fetch the Photos library: \(reason)"
        case .deletionCancelled:
            "Deletion was cancelled."
        }
    }
}

