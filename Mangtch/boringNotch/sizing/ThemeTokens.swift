import SwiftUI

/// Global panel chrome colors. Domain-specific colors (KBO live red,
/// Timer state colors) live in widget-scoped *ThemeTokens introduced in
/// step 7c.
enum ThemeTokens {
    // MARK: Panel surface
    //
    // Two variants: in **light** system appearance the panel sits slightly
    // raised off pure black so the chrome reads as a soft dark surface
    // against the bright menubar; in **dark** system appearance the panel
    // is pitch black so it blends into the OLED-black menubar. Content
    // text stays white in both modes (`.preferredColorScheme(.dark)` on
    // `ContentView`), so the panel is always a dark "color scheme" — only
    // the *shade* changes with system appearance.
    static let panelBackgroundLight = Color(white: 0.22)
    /// Pitch black so the panel merges with the OLED-black menu bar.
    /// Row-tint compositing on this background is handled at the row
    /// level (see `KBORowTokens.rowBaselineTint`), not here.
    static let panelBackgroundDark = Color.black
    static let wingFillLight = Color(white: 0.08)
    /// Wings stay jet black so they merge with the OLED-black menu bar.
    /// Wing surfaces don't carry row tints, so the composition issue that
    /// drives `panelBackgroundDark` away from pure black doesn't apply.
    static let wingFillDark = Color.black
    /// Convenience selector for views that already know the system mode.
    static func panelBackground(systemDark: Bool) -> Color {
        systemDark ? panelBackgroundDark : panelBackgroundLight
    }
    static func wingFill(systemDark: Bool) -> Color {
        systemDark ? wingFillDark : wingFillLight
    }

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
