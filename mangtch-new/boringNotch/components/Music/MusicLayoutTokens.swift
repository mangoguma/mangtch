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
}
