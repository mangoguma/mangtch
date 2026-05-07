import SwiftUI
import AppKit

/// Thin NotchWidget wrapper over boring.notch's existing MusicManager.
/// Compact views read MusicManager.shared directly; expanded view reuses
/// NotchHomeView's MusicPlayerView (which already handles all playback UI).
@MainActor
final class MusicPlayerWidget: NotchWidget {
    let id = "music-player"
    let displayName = "Music"
    let icon = "music.note"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    /// Dynamic — sized to the current track's text so the right-wing
    /// title/artist never truncate. Mirrors KBOWidget's content-driven
    /// approach. Layout breakdown for the right wing (`MusicCompactInfo`):
    ///   textBlock = max(titleWidth, artistWidth)
    ///   transport = 22*3 + 6*2  (three controls, two inter-button gaps)
    ///   wingContent = textBlock + 10 + transport + 16 (outer HStack +
    ///                 .padding(.horizontal, 8))
    /// Total panel width = notchHole + wingContent * 2 (symmetric wings).
    /// Floor uses a default-width track so wings don't degenerate when
    /// no track is loaded.
    var preferredPanelWidth: CGFloat? {
        let music = MusicManager.shared
        let title = music.songTitle
        let artist = music.artistName
        let titleW = Self.textWidth(title.isEmpty ? "Track Title" : title,
                                    size: 11, weight: .semibold)
        let artistW = Self.textWidth(artist.isEmpty ? "Artist" : artist,
                                     size: 10, weight: .regular)
        let textBlock = max(titleW, artistW)
        let transport: CGFloat = 22 * 3 + 6 * 2
        let wingContent = textBlock + 10 + transport + 16
        // Notch width factored in by chrome; we just declare total panel
        // width assuming a typical hole (~200pt). Chrome subtracts the
        // actual hole and halves to derive wingWidth.
        let notchHole: CGFloat = 200
        return notchHole + wingContent * 2
    }

    /// Static — the expanded music UI (album art + title + progress)
    /// fits comfortably in 260pt. Album art square is sized off this.
    var preferredPanelHeight: CGFloat? { 260 }

    func makeCompactView() -> AnyView {
        AnyView(MusicCompactArtwork())
    }

    func makeExpandedView() -> AnyView {
        AnyView(MusicExpandedView())
    }

    func activate() {}
    func deactivate() {}

    /// Text-width helper using AppKit metrics. Same pattern as
    /// `KBOWidget.inlineStarterSlotWidth` — keeps width derivation
    /// deterministic without measuring the rendered SwiftUI tree.
    @MainActor
    private static func textWidth(_ string: String,
                                  size: CGFloat,
                                  weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let measured = (string as NSString)
            .size(withAttributes: [.font: font])
            .width
        return ceil(measured)
    }
}

// MARK: - Compact left-wing: album art square

struct MusicCompactArtwork: View {
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        Image(nsImage: music.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .opacity(music.isPlayerIdle ? 0.4 : 1)
    }
}

// MARK: - Compact right-wing: title + artist + prev/play/next buttons

struct MusicCompactInfo: View {
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(music.songTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(music.artistName)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                controlButton(icon: "backward.fill")
                    .wingHitZone(.musicPrev)
                controlButton(icon: music.isPlaying ? "pause.fill" : "play.fill")
                    .wingHitZone(.musicPlayPause)
                controlButton(icon: "forward.fill")
                    .wingHitZone(.musicNext)
            }
        }
        .padding(.horizontal, 8)
    }

    private func controlButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 22, height: 22)
    }
}

// MARK: - Expanded: reuse boring.notch's MusicPlayerView

/// Hosts MusicPlayerView which requires a matched-geometry Namespace.
/// The namespace is owned here so it lives for the widget's lifetime.
struct MusicExpandedView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Namespace private var albumArtNamespace

    var body: some View {
        MusicPlayerView(albumArtNamespace: albumArtNamespace)
    }
}
