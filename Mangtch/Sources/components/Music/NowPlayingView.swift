import SwiftUI

// MARK: - Compact Artwork View (Left Wing)

/// Shows album art thumbnail + playing indicator. Hovering swaps to
/// playback controls — left wing is the music wing now, including the
/// transport buttons that used to live on the right.
struct CompactArtworkView: View {
    let viewModel: MusicPlayerViewModel
    @Environment(\.notchHostWindow) private var hostWindow
    /// Read the per-window VM so this wing reflects *this* panel's hover
    /// state in multi-display setups. Falls back to primary if the env
    /// value isn't injected (e.g. previews, settings host).
    private var notchVM: NotchViewModel { hostWindow?.viewModel ?? NotchViewModel.shared }

    var body: some View {
        let isHovering = notchVM.hoveredWing == .left
        // Use a ZStack with opacity instead of an if/else swap so the
        // button views stay alive in the SwiftUI tree across hover
        // transitions — SwiftUI was tearing them down between mouseDown
        // and mouseUp, killing every click.
        ZStack {
            HStack(spacing: 6) {
                artworkThumbnail
                if viewModel.isPlaying {
                    AudioVisualizerView(isPlaying: true)
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 12)
                }
            }
            .opacity(isHovering ? 0 : 1)
            .allowsHitTesting(!isHovering)

            compactControls
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }

    private var compactControls: some View {
        // .onTapGesture instead of SwiftUI Button — Button's gesture
        // recognizer only fires its action when the hosting window is
        // key, and our notch panel deliberately stays non-key while
        // hovered (keeping focus on the user's foreground app).
        // onTapGesture has no such requirement.
        HStack(spacing: 2) {
            Image(systemName: "backward.fill")
                .font(.system(size: 9))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .wingHitZone(.musicPrev)

            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .wingHitZone(.musicPlayPause)

            Image(systemName: "forward.fill")
                .font(.system(size: 9))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .wingHitZone(.musicNext)
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Artwork Thumbnail

    @ViewBuilder
    private var artworkThumbnail: some View {
        Group {
            if let artwork = viewModel.currentArtwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Compact Info View (Right Wing)

/// Shows track title/artist on the right wing. Static — playback
/// controls moved to the left wing's CompactArtworkView so the right
/// wing is free for KBO ticker / future widget overlays.
struct CompactInfoView: View {
    let viewModel: MusicPlayerViewModel

    var body: some View {
        // Wing width is owned by NotchViewModel (panel-derived, plus a
        // brief boost during track-change previews). This view fills
        // whatever it's given; MarqueeText scrolls when the title is
        // wider than the wing — no intrinsic-width tricks here, those
        // fought the parent frame and produced clipped/jumpy chrome.
        // Right wing is on the user's right — outer alignment is
        // trailing so the title/artist sit at the screen edge rather
        // than crowded against the notch when expanded.
        HStack(spacing: 6) {
            if let info = viewModel.nowPlaying, !info.title.isEmpty {
                VStack(alignment: .trailing, spacing: 1) {
                    MarqueeText(info.title, font: .system(size: 11, weight: .semibold), isActive: viewModel.isPlaying)
                    MarqueeText(info.artist, font: .system(size: 10), isActive: viewModel.isPlaying)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No music")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
