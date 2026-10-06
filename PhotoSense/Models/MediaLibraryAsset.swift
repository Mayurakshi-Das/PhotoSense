import Foundation

struct MediaLibraryAsset: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: MediaAssetKind
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let location: MediaLocationCoordinate?
    let source: MediaAssetSource
    let isFavorite: Bool
    let isHidden: Bool
    let isScreenshot: Bool
    let resources: [MediaResourceDescriptor]
}
