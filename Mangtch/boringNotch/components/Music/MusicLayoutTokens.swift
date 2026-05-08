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
    /// wings. Halved from the previous `480` so the resting wings sit
    /// flush against the notch and don't dominate the menu bar; full
    /// title/artist text becomes visible only on track change via
    /// `BoringViewModel.previewPanelWidth` (text-fit measurement).
    static let compactWidth: CGFloat = 325
    /// Defensive floor — clamps the closed-state panel width.
    static let compactMinWidth: CGFloat = 285
    /// Wing-hover boost target. Compact wing width (≈62pt at `compactWidth=325`
    /// + 200pt notch) is too narrow to host the transport controls (3×22 +
    /// 2×6 + 2×8 = 94pt). When the cursor enters the right wing, the panel
    /// widens to this so prev/play/next render with breathing room — wing
    /// becomes ~110pt, fits 94pt of buttons plus 16pt of headroom.
    /// Reverts on hover exit, layered with the track-change preview via
    /// `max()` so the larger of the two wins.
    static let hoverWidth: CGFloat = 420
}
