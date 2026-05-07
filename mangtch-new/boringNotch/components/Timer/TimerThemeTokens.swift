import SwiftUI

/// Timer-domain colors. Replaces the hand-rolled palette that lived as
/// stored properties on `TimerExpandedView`. Sizes/whites stay literal
/// because they're tuned for the specific dark panel surface, not
/// derivable from system semantic colors.
enum TimerThemeTokens {
    /// Mode picker background, ± button background, segmented surface.
    /// Was `Color(white: 0.22)`.
    static let surfaceMedium = Color(white: 0.22)
    /// Progress ring track. Was `Color(white: 0.28)`.
    static let trackBackground = Color(white: 0.28)
    /// Compact ring track on top of the dark wing — translucent white reads
    /// against the wing fill without competing with the colored progress arc.
    static let compactRingTrack = Color.white.opacity(0.15)
    /// Paused state accent (start/pause toggle color when running).
    static let pausedAccent = Color.yellow
}
