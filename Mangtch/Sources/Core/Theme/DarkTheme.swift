import SwiftUI

/// Dark theme with deeper shadows and reduced brightness
struct DarkTheme: NotchTheme {
    // MARK: - Materials & Effects

    var panelMaterial: Material {
        .thickMaterial
    }

    var panelTint: Color {
        // Near-opaque black so the panel always reads as black, regardless
        // of wallpaper or what's behind the menu bar. Translucent values
        // (≤0.6) bleed too much desktop colour through and make small
        // indicators (rings, thin strokes) hard to see.
        Color.black.opacity(0.92)
    }

    var shadowColor: Color {
        .black
    }

    var shadowRadius: CGFloat {
        16
    }

    var shadowOpacity: Double {
        0.4
    }

    // MARK: - Geometry

    var panelCornerRadius: CGFloat {
        16
    }

    // MARK: - Colors

    var accentColor: Color {
        .blue
    }

    var textPrimary: Color {
        .white
    }

    var textSecondary: Color {
        Color.white.opacity(0.6)
    }

    var backgroundPrimary: Color {
        Color(white: 0.12)
    }

    var backgroundSecondary: Color {
        Color(white: 0.18)
    }

    // MARK: - HUD-specific

    var hudSliderTrackColor: Color {
        Color.white.opacity(0.15)
    }

    var hudSliderFillColor: Color {
        .white
    }

    var hudIconColor: Color {
        Color.white.opacity(0.7)
    }
}
