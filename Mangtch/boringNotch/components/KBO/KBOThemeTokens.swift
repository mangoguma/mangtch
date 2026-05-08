import SwiftUI

/// KBO-domain colors. Lives next to the views (not in /sizing) because
/// these encode broadcasting conventions, not chrome — `live` matches
/// every Korean broadcaster's red LIVE chip, `win` matches the "승"
/// badge color used across Naver/Daum game logs, base colors mirror the
/// MLB-derived diamond palette every Korean app converged on.
enum KBOThemeTokens {
    /// LIVE pulse dot, live status chip, "현재" markers.
    static let live = Color.red
    /// Winner badge ("승") fill — never paired with red so finished games
    /// don't read as "still live".
    static let win = Color.blue
    /// Base diamond fill when a runner is on.
    static let baseFilled = Color.yellow
    /// B/S/O dot palette — broadcast standard.
    static let ballsFilled = Color.green
    static let strikesFilled = Color.yellow
    static let outsFilled = Color.red
    /// Pitcher/batter row text inside the dark live state pill.
    static let liveText = Color.white
    /// Right-wing compact hover background, expanded compact mode picker
    /// fill — driven by the system accent so users' taste carries through.
    static let accentSurface = Color.accentColor

    /// Baseline luminance laid under each KBO row when the panel is in
    /// the jet-black dark variant. Existing row tints (`primary.opacity(.04..)`)
    /// were tuned for the upstream Mangtch DarkTheme panel
    /// (`Color(white: 0.12)`); on a pitch-black panel the same tints
    /// composite to too-dim values and rows lose their card-like read.
    /// This baseline simulates that 12% panel underlay only behind the
    /// rows, so the panel chrome stays merged with the menu bar.
    static let rowBaselineTint = Color.white.opacity(0.06)
}
