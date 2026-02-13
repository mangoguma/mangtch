import SwiftUI

/// Protocol defining the visual tokens for NotchApp themes
protocol NotchTheme {
    // MARK: - Materials & Effects

    /// Material used for panel backgrounds
    var panelMaterial: Material { get }

    /// Shadow color for panel and HUD elements
    var shadowColor: Color { get }

    /// Shadow blur radius
    var shadowRadius: CGFloat { get }

    /// Shadow opacity (0.0 - 1.0)
    var shadowOpacity: Double { get }

    // MARK: - Geometry

    /// Corner radius for panel elements
    var panelCornerRadius: CGFloat { get }

    // MARK: - Colors

    /// Primary accent color for interactive elements
    var accentColor: Color { get }

    /// Primary text color
    var textPrimary: Color { get }

    /// Secondary text color (subdued)
    var textSecondary: Color { get }

    /// Primary background color
    var backgroundPrimary: Color { get }

    /// Secondary background color (for layering)
    var backgroundSecondary: Color { get }

    // MARK: - HUD-specific

    /// HUD slider track background color
    var hudSliderTrackColor: Color { get }

    /// HUD slider fill color
    var hudSliderFillColor: Color { get }

    /// HUD icon color
    var hudIconColor: Color { get }

    /// Whether this theme dynamically changes (e.g. album art theme)
    var isDynamic: Bool { get }
}

// Default implementation
extension NotchTheme {
    var isDynamic: Bool { false }
}
