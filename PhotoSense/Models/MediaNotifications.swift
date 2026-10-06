import Foundation

extension Notification.Name {
    /// Broadcast when media assets or Bin items are modified (e.g., deleted or removed).
    static let mediaAssetsDidChange = Notification.Name("PhotoSense.mediaAssetsDidChange")
}
