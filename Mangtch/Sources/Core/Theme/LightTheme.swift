import SwiftUI

/// Light theme with brighter colors and softer shadows
struct LightTheme: NotchTheme {
    // MARK: - Materials & Effects

    var panelMaterial: Material {
        .ultraThinMaterial
    }

    var shadowColor: Color {
        .black
    }

    var shadowRadius: CGFloat {
        10
    }

    var shadowOpacity: Double {
        0.12
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
        .black
    }

    var textSecondary: Color {
        Color.black.opacity(0.6)
    }

    var backgroundPrimary: Color {
        Color(white: 0.96)
    }

    var backgroundSecondary: Color {
        Color(white: 0.92)
    }

    // MARK: - HUD-specific

    var hudSliderTrackColor: Color {
        Color.black.opacity(0.1)
    }

    var hudSliderFillColor: Color {
        .black
    }

    var hudIconColor: Color {
        Color.black.opacity(0.6)
    }
}
