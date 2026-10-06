import Foundation

enum MediaLibraryAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
    case unknown

    var canReadLibrary: Bool {
        switch self {
        case .authorized, .limited:
            true
        case .notDetermined, .denied, .restricted, .unknown:
            false
        }
    }

    var title: String {
        switch self {
        case .notDetermined:
            "Photos Access Needed"
        case .authorized:
            "Photos Access Granted"
        case .limited:
            "Limited Photos Access"
        case .denied:
            "Photos Access Denied"
        case .restricted:
            "Photos Access Restricted"
        case .unknown:
            "Photos Access Unavailable"
        }
    }

    var message: String {
        switch self {
        case .notDetermined:
            "PhotoSense needs read access to build a local metadata index."
        case .authorized:
            "PhotoSense can index the full visible library."
        case .limited:
            "PhotoSense will index only the assets selected in Limited Photos access."
        case .denied:
            "Allow Photos access in Settings to analyze the library."
        case .restricted:
            "This device or account restricts Photos access."
        case .unknown:
            "The current Photos authorization state is not recognized."
        }
    }
}
