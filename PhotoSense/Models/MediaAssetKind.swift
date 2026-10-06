import Foundation

enum MediaAssetKind: String, Codable, Hashable, Sendable {
    case photo
    case video
    case unknown
}

enum MediaAssetSource: String, Codable, Hashable, Sendable {
    case userLibrary
    case cloudShared
    case iTunesSynced
    case unknown
}

enum MediaResourceKind: String, Codable, Hashable, Sendable {
    case photo
    case video
    case audio
    case pairedVideo
    case fullSizePhoto
    case fullSizeVideo
    case adjustmentData
    case adjustmentBasePhoto
    case adjustmentBaseVideo
    case adjustmentBasePairedVideo
    case alternatePhoto
    case fullSizePairedVideo
    case photoProxy
    case unknown
}
