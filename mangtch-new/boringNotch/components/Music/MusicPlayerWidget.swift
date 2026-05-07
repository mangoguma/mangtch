import SwiftUI

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
    var preferredPanelWidth: CGFloat? { 380 }

    func makeCompactView() -> AnyView {
        AnyView(MusicCompactArtwork())
    }

    func makeExpandedView() -> AnyView {
        AnyView(MusicExpandedView())
    }

    func activate() {}
    func deactivate() {}
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
