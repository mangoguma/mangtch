import SwiftUI

struct ExpandedPlayerView: View {
    let viewModel: MusicPlayerViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var spotifyAuth = SpotifyAuth.shared

    /// Show the heart any time there's a track. Hiding it when Spotify
    /// wasn't authorized made people think the feature was broken — now
    /// the click instead opens Settings so they can finish auth.
    private var canShowLikeButton: Bool {
        musicManager.nowPlaying != nil
    }

    /// True when toggling actually does something. Spotify needs Web API
    /// auth (its AppleScript `starred` is read-only since Liked Songs
    /// replaced Star); Apple Music works through AppleScript without auth.
    private var canToggleLike: Bool {
        switch musicManager.activePlayer {
        case .spotify:
            return spotifyAuth.isAuthorized && musicManager.nowPlaying?.trackID != nil
        case .appleMusic:
            return true
        case .none:
            return false
        }
    }

    private func handleLikeTap() {
        if canToggleLike {
            musicManager.toggleLike()
        } else {
            // Unauthorized Spotify (or no detected player): send the user
            // to Settings to finish auth instead of silently no-op'ing.
            MenuBarManager.shared.openSettings()
        }
    }

    var body: some View {
        let artwork = musicManager.currentArtwork
        let dominant = musicManager.dominantColor
        let secondary = musicManager.secondaryColor

        VStack(spacing: 0) {
            // Artwork + info/transport + lyrics + like
            HStack(alignment: .top, spacing: 14) {
                // Album artwork
                artworkImage(artwork, dominant: dominant)
                    .frame(width: 80, height: 80)

                // Track info + transport (fixed-ish so lyrics has room)
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

                    transportControls
                }
                .frame(width: 140, alignment: .leading)

                // Synced lyrics — flexes to fill the remaining width
                LyricsPanel(viewModel: viewModel, dominant: dominant)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)

                // Like button — always visible when there's a track.
                if canShowLikeButton {
                    Button(action: handleLikeTap) {
                        Image(systemName: musicManager.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 13))
                            .foregroundStyle(musicManager.isLiked
                                ? Color.red
                                : themeManager.currentTheme.textSecondary.opacity(0.6))
                            .opacity(canToggleLike ? 1 : 0.5)
                    }
                    .buttonStyle(PlayerButtonStyle())
                    .help(canToggleLike
                          ? (musicManager.isLiked ? "Unlike" : "Like")
                          : "Connect Spotify in Settings to enable Likes")
                    .padding(.top, 32)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Progress bar (seekable)
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
        let rawFill = dominant != .clear ? dominant : themeManager.currentTheme.accentColor
        // 3pt UI element on a black panel needs 3:1 minimum (WCAG AA).
        let fillColor = rawFill.contrastBoosted(against: .black, targetRatio: 3.0)

        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(themeManager.currentTheme.backgroundSecondary.opacity(0.6))
                        .frame(height: 3)

                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(0, geo.size.width * viewModel.progress), height: 3)
                        .animation(viewModel.isScrubbing ? nil : .linear(duration: 1.0 / 60.0),
                                   value: viewModel.progress)
                }
                // Tall transparent hit area so the 3pt bar is easy to grab.
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = value.location.x / max(1, geo.size.width)
                            viewModel.previewSeek(toFraction: f)
                        }
                        .onEnded { value in
                            let f = value.location.x / max(1, geo.size.width)
                            viewModel.commitSeek(toFraction: f)
                        }
                )
            }
            .frame(height: 14)

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

// MARK: - Lyrics Panel

private struct LyricsPanel: View {
    let viewModel: MusicPlayerViewModel
    let dominant: Color
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var lyricsManager = LyricsManager.shared

    var body: some View {
        Group {
            switch lyricsManager.lyrics {
            case .synced(let lines):
                syncedView(lines: lines)
            case .plain(let text):
                plainView(text: text)
            case .none:
                placeholderView
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .onAppear { loadIfNeeded() }
        .onChange(of: viewModel.nowPlaying?.title) { _, _ in loadIfNeeded() }
        .onChange(of: viewModel.nowPlaying?.artist) { _, _ in loadIfNeeded() }
        // NowPlaying often delivers duration on a later tick than title/artist.
        // Round to seconds so we don't thrash on sub-second jitter.
        .onChange(of: Int((viewModel.nowPlaying?.duration ?? 0).rounded())) { _, _ in loadIfNeeded() }
    }

    private func loadIfNeeded() {
        guard let info = viewModel.nowPlaying,
              !info.title.isEmpty, !info.artist.isEmpty else { return }
        lyricsManager.load(for: info)
    }

    @ViewBuilder
    private var placeholderView: some View {
        let label = lyricsManager.isLoading ? "Loading lyrics…" : "No lyrics found"
        Text(label)
            .font(.system(size: 10))
            .foregroundStyle(themeManager.currentTheme.textSecondary.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func plainView(text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func syncedView(lines: [LRCLine]) -> some View {
        // Active line index is derived from viewModel.progress, which the
        // display-link timer updates ~60Hz, so the highlight tracks playback
        // smoothly without us running our own timer.
        let elapsed = (viewModel.nowPlaying?.duration ?? 0) * viewModel.progress
        let activeIdx = currentIndex(for: elapsed, in: lines) ?? -1
        // Lift the dominant colour against the black panel so a dark or
        // muddy artwork-derived hue still clears WCAG AA on the highlight.
        let highlight = (dominant != .clear ? dominant : themeManager.currentTheme.textPrimary)
            .contrastBoosted(against: .black, targetRatio: 4.5)

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 11,
                                          weight: idx == activeIdx ? .semibold : .regular))
                            .foregroundStyle(idx == activeIdx
                                ? highlight
                                : themeManager.currentTheme.textSecondary.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: activeIdx) { _, newIdx in
                guard newIdx >= 0 else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }

    private func currentIndex(for time: TimeInterval, in lines: [LRCLine]) -> Int? {
        var lo = 0, hi = lines.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return idx >= 0 ? idx : nil
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
