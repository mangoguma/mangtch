import SwiftUI
import AppKit

/// Dynamic theme that derives colors from the currently playing track's album artwork.
/// When no artwork is available, falls back to DefaultTheme colors.
struct AlbumArtTheme: NotchTheme {

    let dominantColor: Color
    let secondaryColor: Color
    let isDark: Bool

    init(palette: ColorExtractor.Palette) {
        self.dominantColor = Color(nsColor: palette.dominant)
        self.secondaryColor = Color(nsColor: palette.secondary)
        self.isDark = palette.isDark
    }

    init() {
        self.dominantColor = Color(white: 0.15)
        self.secondaryColor = Color(white: 0.3)
        self.isDark = true
    }

    // MARK: - Materials & Effects

    var panelMaterial: Material {
        .ultraThinMaterial
    }

    var shadowColor: Color {
        dominantColor.opacity(0.6)
    }

    var shadowRadius: CGFloat { 16 }
    var shadowOpacity: Double { 0.35 }

    // MARK: - Geometry

    var panelCornerRadius: CGFloat { 16 }

    // MARK: - Colors

    var accentColor: Color {
        secondaryColor
    }

    var textPrimary: Color {
        isDark ? .white : .black
    }

    var textSecondary: Color {
        isDark ? .white.opacity(0.7) : .black.opacity(0.6)
    }

    var backgroundPrimary: Color {
        dominantColor.opacity(0.3)
    }

    var backgroundSecondary: Color {
        secondaryColor.opacity(0.2)
    }

    // MARK: - HUD-specific

    var hudSliderTrackColor: Color {
        isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    var hudSliderFillColor: Color {
        secondaryColor
    }

    var hudIconColor: Color {
        textSecondary
    }
}
