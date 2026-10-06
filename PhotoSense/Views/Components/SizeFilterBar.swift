import SwiftUI

/// A compact, native iOS-style filter bar for file size filtering.
struct SizeFilterBar<T: Hashable & CustomStringConvertible>: View {
    let options: [T]
    @Binding var selected: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selected == option
                    Button {
                        withAnimation(PhotoSenseTheme.springQuick) {
                            selected = option
                        }
                    } label: {
                        Text(option.description)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.primary : Color(.secondarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }
}

/// Standard size filter options for All Videos
enum VideoSizeFilter: String, CaseIterable, CustomStringConvertible, Hashable {
    case all = "All"
    case under100MB = "< 100 MB"
    case under500MB = "< 500 MB"
    case under1GB = "< 1 GB"
    case over1GB = "> 1 GB"

    var description: String { rawValue }

    func matches(bytes: Int64?) -> Bool {
        guard let bytes else { return self == .all }
        let mb = Double(bytes) / (1024 * 1024)
        switch self {
        case .all:
            return true
        case .under100MB:
            return mb < 100
        case .under500MB:
            return mb < 500
        case .under1GB:
            return mb < 1024
        case .over1GB:
            return mb >= 1024
        }
    }
}

/// Size filter options for Large Videos
enum LargeVideoSizeFilter: String, CaseIterable, CustomStringConvertible, Hashable {
    case all = "All"
    case min100MB = "100 MB+"
    case min500MB = "500 MB+"
    case min1GB = "1 GB+"
    case min2GB = "2 GB+"

    var description: String { rawValue }

    func matches(bytes: Int64) -> Bool {
        let mb = Double(bytes) / (1024 * 1024)
        switch self {
        case .all:
            return true
        case .min100MB:
            return mb >= 100
        case .min500MB:
            return mb >= 500
        case .min1GB:
            return mb >= 1024
        case .min2GB:
            return mb >= 2048
        }
    }
}

/// Size filter options for Duplicate Videos
enum DuplicateVideoSizeFilter: String, CaseIterable, CustomStringConvertible, Hashable {
    case all = "All"
    case under100MB = "< 100 MB"
    case between100And500MB = "100–500 MB"
    case min500MB = "500 MB+"
    case min1GB = "1 GB+"

    var description: String { rawValue }

    func matches(maxBytesInGroup: Int64) -> Bool {
        let mb = Double(maxBytesInGroup) / (1024 * 1024)
        switch self {
        case .all:
            return true
        case .under100MB:
            return mb < 100
        case .between100And500MB:
            return mb >= 100 && mb < 500
        case .min500MB:
            return mb >= 500
        case .min1GB:
            return mb >= 1024
        }
    }
}
