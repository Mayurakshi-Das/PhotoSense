import Foundation

struct MediaResourceDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: MediaResourceKind
    let uniformTypeIdentifier: String?
    let originalFilename: String?
    let fileSize: Int64?

    init(
        id: String,
        kind: MediaResourceKind,
        uniformTypeIdentifier: String?,
        originalFilename: String?,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.originalFilename = originalFilename
        self.fileSize = fileSize
    }
}
