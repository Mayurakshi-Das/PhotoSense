import Foundation

enum MediaIndexingError: LocalizedError, Sendable {
    case authorizationRequired(MediaLibraryAuthorizationStatus)

    var errorDescription: String? {
        switch self {
        case .authorizationRequired(let status):
            status.message
        }
    }
}
