import Foundation

enum DashboardCategory: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case screenshots
    case videos
    case duplicatePhotos
    case duplicateVideos
    case similarPhotos
    case largeVideos
    case bin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots:
            "Screenshots"
        case .videos:
            "Videos"
        case .duplicatePhotos:
            "Duplicate Photos"
        case .duplicateVideos:
            "Duplicate Videos"
        case .similarPhotos:
            "Similar Photos"
        case .largeVideos:
            "Large Videos"
        case .bin:
            "Bin"
        }
    }

    var subtitle: String {
        switch self {
        case .screenshots:
            "Indexed from Photos metadata"
        case .videos:
            "Indexed videos in the library"
        case .duplicatePhotos:
            "Vision feature-print detection"
        case .duplicateVideos:
            "Multi-point keyframe verification"
        case .similarPhotos:
            "Cosine similarity via Vision embeddings"
        case .largeVideos:
            "File-size engine pending"
        case .bin:
            "Items deleted through PhotoSense"
        }
    }

    var systemImage: String {
        switch self {
        case .screenshots:
            "camera.viewfinder"
        case .videos:
            "video"
        case .duplicatePhotos:
            "rectangle.on.rectangle"
        case .duplicateVideos:
            "film.stack"
        case .similarPhotos:
            "sparkles.rectangle.stack"
        case .largeVideos:
            "externaldrive.badge.icloud"
        case .bin:
            "trash"
        }
    }
}
