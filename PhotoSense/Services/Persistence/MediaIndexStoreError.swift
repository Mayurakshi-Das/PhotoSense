import Foundation

enum MediaIndexStoreError: LocalizedError, Sendable {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            "The media index store is unavailable: \(reason)"
        }
    }
}
