import SwiftUI

struct NowPlayingView: View {
    let viewModel: MusicPlayerViewModel

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Album art thumbnail
            artworkThumbnail

            // Track info or controls
            if let info = viewModel.nowPlaying, !info.title.isEmpty {
                if isHovering {
                    // Compact playback controls on hover
                    compactControls
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    // Track info
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            MarqueeText(info.title, font: .system(size: 11, weight: .semibold), isActive: viewModel.isPlaying)

                            if viewModel.isPlaying {
                                AudioVisualizerView(isPlaying: true)
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 12)
                            }
                        }

                        MarqueeText(info.artist, font: .system(size: 10), isActive: viewModel.isPlaying)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
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
