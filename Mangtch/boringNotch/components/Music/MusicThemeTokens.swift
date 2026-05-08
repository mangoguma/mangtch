import SwiftUI

/// Music-widget colors. Most of the music chrome inherits from
/// `ThemeTokens` (panel/wing); the values here are specific to the lyrics
/// card and the active-line palette.
enum MusicThemeTokens {
    /// Lyrics card surface — sits on top of the dark panel and lifts the
    /// lyric text off the background just enough to read as a card.
    static let lyricsCardSurface = Color.white.opacity(0.04)
    /// Inactive synced-lyric line. Active line uses album-art-derived
    /// `Color.ensureMinimumBrightness` so the highlight tracks artwork.
    static let inactiveLyric: Color = .secondary.opacity(0.55)
    /// "Loading lyrics…" placeholder text.
    static let lyricsPlaceholder: Color = .secondary.opacity(0.6)
}
