import SwiftUI

// MARK: - Compact Artwork View (Left Wing)

/// Shows album art thumbnail + playing indicator.
/// Used in the left wing of the notch.
struct CompactArtworkView: View {
    let viewModel: MusicPlayerViewModel

    var body: some View {
        HStack(spacing: 6) {
            // Album art thumbnail
            artworkThumbnail

            // Playing indicator
            if viewModel.isPlaying {
                AudioVisualizerView(isPlaying: true)
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 12)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
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

/// Shows track title/artist, switches to playback controls on hover.
/// Used in the right wing of the notch.
struct CompactInfoView: View {
    let viewModel: MusicPlayerViewModel

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let info = viewModel.nowPlaying, !info.title.isEmpty {
                if isHovering {
                    // Compact playback controls on hover
                    compactControls
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    // Track info
                    VStack(alignment: .leading, spacing: 1) {
                        MarqueeText(info.title, font: .system(size: 11, weight: .semibold), isActive: viewModel.isPlaying)

                        MarqueeText(info.artist, font: .system(size: 10), isActive: viewModel.isPlaying)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            } else {
                Text("No music")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Compact Controls

    private var compactControls: some View {
        HStack(spacing: 2) {
            Button(action: { viewModel.previousTrack() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 9))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.togglePlayPause() }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.nextTrack() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 9))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.primary)
    }
}
