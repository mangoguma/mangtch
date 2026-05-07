import SwiftUI

/// Music widget's pixel-design canvas. boring.notch's MusicPlayerView,
/// AlbumArtView, and MusicControlsView are pixel-laid against this exact
/// canvas — 640pt wide leaves album art + controls + lyrics panel at
/// their native proportions, 190pt tall keeps the slider/marquee row
/// from being cropped. These are NOT global panel dimensions; KBO/Timer
/// declare their own content-driven ranges.
enum MusicLayoutTokens {
    static let expandedWidth: CGFloat = 640
    static let expandedHeight: CGFloat = 190

    /// Compact wing target — closed-state panel width when Music owns the
    /// wings. Mirrors Mangtch reference's `preferredPanelWidth: 480`: wide
    /// enough for a typical title + artist + 3 transport buttons without
    /// truncation, narrow enough that the wings don't dominate the menu
    /// bar when nothing is expanded.
    static let compactWidth: CGFloat = 480
    /// Defensive floor — short titles like "—" never collapse below this.
    static let compactMinWidth: CGFloat = 380
}
