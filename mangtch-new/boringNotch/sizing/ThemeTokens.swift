import SwiftUI

/// Global panel chrome colors. Domain-specific colors (KBO live red,
/// Timer state colors) live in widget-scoped *ThemeTokens introduced in
/// step 7c.
enum ThemeTokens {
    // MARK: Panel surface
    /// Expanded panel background. Was `Color(white: 0.14)`.
    static let panelBackground = Color(white: 0.14)
    /// Wing fill (left/right wings + notch bar covering the hardware notch).
    static let wingFill = Color.black

    // MARK: Text
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.55)

    // MARK: Accent
    /// System accent — respects user's macOS preference.
    static let accent = Color.accentColor
    /// Selected switcher tab background fill.
    static let switcherSelectedFill = Color.accentColor.opacity(0.25)
}
