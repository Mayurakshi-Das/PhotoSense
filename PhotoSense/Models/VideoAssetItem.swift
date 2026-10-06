import Foundation

struct VideoAssetItem: Identifiable, Hashable, Sendable {
    let id: String
    let duration: TimeInterval
    let fileSize: Int64
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    var rank: Int = 0

    var formattedDuration: String {
        guard duration > 0 else { return "00:00" }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var resolutionString: String {
        guard pixelWidth > 0 && pixelHeight > 0 else { return "" }
        if (pixelWidth >= 3840 && pixelHeight >= 2160) || (pixelWidth >= 2160 && pixelHeight >= 3840) {
            return "4K"
        } else if (pixelWidth >= 1920 && pixelHeight >= 1080) || (pixelWidth >= 1080 && pixelHeight >= 1920) {
            return "1080p"
        } else if (pixelWidth >= 1280 && pixelHeight >= 720) || (pixelWidth >= 720 && pixelHeight >= 1280) {
            return "720p"
        } else {
            return "\(pixelWidth)×\(pixelHeight)"
        }
    }
}
