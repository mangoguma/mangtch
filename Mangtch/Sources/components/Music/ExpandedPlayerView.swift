import SwiftUI

struct ExpandedPlayerView: View {
    let viewModel: MusicPlayerViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var spotifyAuth = SpotifyAuth.shared

    /// Heart only makes sense when we can actually toggle the source's
    /// "liked" state. For Spotify that means signed-in (Web API); Apple
    /// Music still works through AppleScript without auth.
    private var canShowLikeButton: Bool {
        switch musicManager.activePlayer {
        case .spotify:
            return spotifyAuth.isAuthorized && musicManager.nowPlaying?.trackID != nil
        case .appleMusic:
            return true
        case .none:
            return false
        }
    }

    var body: some View {
        let artwork = musicManager.currentArtwork
        let dominant = musicManager.dominantColor
        let secondary = musicManager.secondaryColor

        VStack(spacing: 0) {
            // Artwork + info + controls row
            HStack(spacing: 14) {
                // Album artwork
                artworkImage(artwork, dominant: dominant)
                    .frame(width: 80, height: 80)

                // Track info + transport
                VStack(alignment: .leading, spacing: 4) {
                    if let info = viewModel.nowPlaying {
                        Text(info.title)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .foregroundStyle(themeManager.currentTheme.textPrimary)

                        Text(info.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                            .lineLimit(1)

                        if !info.album.isEmpty {
                            Text(info.album)
                                .font(.system(size: 10))
                                .foregroundStyle(themeManager.currentTheme.textSecondary.opacity(0.5))
                                .lineLimit(1)
                        }
                    } else {
                        Text("Not Playing")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }

                    Spacer().frame(height: 6)

                    // Transport controls + like button
                    HStack(spacing: 0) {
                        transportControls

                        Spacer()

                        // Like button — hidden when there's no working backend
                        // (e.g. Spotify without Web API sign-in)
                        if canShowLikeButton {
                            Button(action: { musicManager.toggleLike() }) {
                                Image(systemName: musicManager.isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 13))
                                    .foregroundStyle(musicManager.isLiked
                                        ? Color.red
                                        : themeManager.currentTheme.textSecondary.opacity(0.6))
                            }
                            .buttonStyle(PlayerButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Progress bar
            progressBar(dominant: dominant)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        // Subtle gradient background tint from artwork colors
        .background {
            if dominant != .clear {
                LinearGradient(
                    colors: [
                        dominant.opacity(0.08),
                        secondary.opacity(0.04),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkImage(_ artwork: NSImage?, dominant: Color) -> some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hue: 0.75, saturation: 0.3, brightness: 0.3),
                            Color(hue: 0.6, saturation: 0.25, brightness: 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 18) {
            Button(action: { viewModel.previousTrack() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(themeManager.currentTheme.textPrimary.opacity(0.8))
            }
            .buttonStyle(PlayerButtonStyle())

            Button(action: { viewModel.togglePlayPause() }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(themeManager.currentTheme.textPrimary)
            }
            .buttonStyle(PlayerButtonStyle())

            Button(action: { viewModel.nextTrack() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(themeManager.currentTheme.textPrimary.opacity(0.8))
            }
            .buttonStyle(PlayerButtonStyle())
        }
    }

    // MARK: - Progress Bar

    @ViewBuilder
    private func progressBar(dominant: Color) -> some View {
        let fillColor = dominant != .clear ? dominant : themeManager.currentTheme.accentColor

        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(themeManager.currentTheme.backgroundSecondary.opacity(0.6))
                        .frame(height: 3)

                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(0, geo.size.width * viewModel.progress), height: 3)
                        .animation(.linear(duration: 1.0 / 60.0), value: viewModel.progress)
                }
            }
            .frame(height: 3)

            HStack {
                Text(viewModel.elapsedFormatted)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(themeManager.currentTheme.textSecondary.opacity(0.6))

                Spacer()

                Text(viewModel.remainingFormatted)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(themeManager.currentTheme.textSecondary.opacity(0.6))
            }
        }
    }
}

// MARK: - Player Button Style

struct PlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
