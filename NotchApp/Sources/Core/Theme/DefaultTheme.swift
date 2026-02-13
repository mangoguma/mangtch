import SwiftUI

/// Default theme matching the current NotchApp visual design
struct DefaultTheme: NotchTheme {
    // MARK: - Materials & Effects

    var panelMaterial: Material {
        .ultraThinMaterial
    }

    var shadowColor: Color {
        .black
    }

    var shadowRadius: CGFloat {
        // Varies by state: 20 for expanded, 8 for hovering
        // Providing a middle ground default
        12
    }

    var shadowOpacity: Double {
        // Varies by state: 0.3 for expanded, 0.15 for hovering
        // Providing a middle ground default
        0.2
    }

    // MARK: - Geometry

    var panelCornerRadius: CGFloat {
        // From NotchViewModel.swift line 26
        16
    }

    // MARK: - Colors

    var accentColor: Color {
        .blue
    }

    var textPrimary: Color {
        .primary
    }

    var textSecondary: Color {
        .secondary
    }

    var backgroundPrimary: Color {
        .clear
    }

    var backgroundSecondary: Color {
        Color(.quaternaryLabelColor)
    }

    // MARK: - HUD-specific

    var hudSliderTrackColor: Color {
        // From HUDSliderView.swift line 21
        Color(.quaternaryLabelColor)
    }

    var hudSliderFillColor: Color {
        // From HUDSliderView.swift line 26
        .white
    }

    var hudIconColor: Color {
        // From HUDSliderView.swift line 13
        .secondary
    }
}
