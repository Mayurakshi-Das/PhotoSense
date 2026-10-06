import SwiftUI

/// Unified design system tokens and styling helpers for PhotoSense.
/// Provides consistent typography, spacing, corner radii, and color schemes
/// aligned with Apple's human interface guidelines for iOS.
enum PhotoSenseTheme {
    // MARK: - Category Colors (Distinct & Tasteful across Light/Dark modes)

    static func categoryColor(for category: DashboardCategory) -> Color {
        switch category {
        case .videos:
            Color(red: 0.38, green: 0.40, blue: 0.95) // Indigo
        case .screenshots:
            Color(red: 0.05, green: 0.68, blue: 0.85) // Cyan
        case .duplicatePhotos:
            Color(red: 0.96, green: 0.38, blue: 0.48) // Rose Coral
        case .duplicateVideos:
            Color(red: 0.65, green: 0.35, blue: 0.88) // Purple
        case .similarPhotos:
            Color(red: 0.15, green: 0.78, blue: 0.65) // Emerald Mint
        case .largeVideos:
            Color(red: 0.98, green: 0.58, blue: 0.15) // Amber Orange
        case .bin:
            Color(red: 0.55, green: 0.56, blue: 0.60) // Neutral Slate
        }
    }

    // MARK: - Brand / Accent Color
    static let accent = Color.blue
    static let reclaimableAccent = Color(red: 0.96, green: 0.38, blue: 0.48) // Rose

    // MARK: - Corner Radii
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    static let cornerRadiusPill: CGFloat = 20

    // MARK: - Spacing & Padding
    static let gridSpacing: CGFloat = 3
    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24

    // MARK: - Animations
    static let springQuick = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let springSmooth = Animation.spring(response: 0.35, dampingFraction: 0.86)
}
