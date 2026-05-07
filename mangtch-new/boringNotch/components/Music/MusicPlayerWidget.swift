import SwiftUI
import AppKit
import Defaults

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
    /// approach.
    var widthRange: WidthRange {
        let music = MusicManager.shared
        let titleW = Self.textWidth(music.songTitle.isEmpty ? "Track Title" : music.songTitle,
                                    size: 11, weight: .semibold)
        let artistW = Self.textWidth(music.artistName.isEmpty ? "Artist" : music.artistName,
                                     size: 10, weight: .regular)
        let textBlock = max(titleW, artistW)
        let transport = LayoutTokens.compactControlSize * 3 + LayoutTokens.compactTransportSpacing * 2
        let wingContent = textBlock + LayoutTokens.compactRowSpacing + transport
                        + LayoutTokens.compactHorizontalPadding * 2
        let notchHole: CGFloat = 200
        let ideal = notchHole + wingContent * 2
        return WidthRange(min: 360, ideal: ideal, max: LayoutTokens.openCanvasWidth)
    }

    /// Static — the expanded music UI (album art + title + progress)
    /// fits comfortably in 260pt. Album art square is sized off this.
    var heightRange: HeightRange { HeightRange(min: 220, ideal: 260, max: 320) }

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
        HStack(spacing: LayoutTokens.compactRowSpacing) {
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

            HStack(spacing: LayoutTokens.compactTransportSpacing) {
                controlButton(icon: "backward.fill")
                    .wingHitZone(.musicPrev)
                controlButton(icon: music.isPlaying ? "pause.fill" : "play.fill")
                    .wingHitZone(.musicPlayPause)
                controlButton(icon: "forward.fill")
                    .wingHitZone(.musicNext)
            }
        }
        .padding(.horizontal, LayoutTokens.compactHorizontalPadding)
    }

    private func controlButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: LayoutTokens.compactControlSize, height: LayoutTokens.compactControlSize)
    }
}

// MARK: - Expanded: reuse boring.notch's MusicPlayerView

/// Hosts MusicPlayerView which requires a matched-geometry Namespace.
/// The namespace is owned here so it lives for the widget's lifetime.
///
/// Layout mirrors boring.notch's `NotchHomeView.mainContent` —
/// `MusicPlayerView` on the left, a fixed-width side slot on the right.
/// Upstream fills that slot with `CalendarView`; we use it for synced
/// lyrics instead, restoring the Mangtch-side lyrics panel and keeping
/// album art at the boring.notch-native size (the HStack-height-sized
/// album square only behaves correctly when something else owns the
/// right portion of the panel).
struct MusicExpandedView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Namespace private var albumArtNamespace

    var body: some View {
        HStack(alignment: .top, spacing: LayoutTokens.musicLyricsGutter) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)
            LyricsPanel()
                .frame(width: 215)
        }
        // Match the 5pt inset that AlbumArtView applies on the left side
        // (NotchHomeView.swift:21 `padding(.all, 5)`). Without this the
        // LyricsPanel's visible box extends 5pt closer to the right chrome
        // than album art does to the left, producing asymmetric margins.
        .padding(.trailing, LayoutTokens.visualBalanceInset)
    }
}

// MARK: - Lyrics Panel
//
// Inlined here (rather than a standalone file) because the Xcode project
// uses a hand-maintained source list — this directory is *not* a
// `PBXFileSystemSynchronizedRootGroup`, so a new .swift file silently
// drops out of the build target. Adding to MusicPlayerWidget.swift keeps
// the file count unchanged and the pbxproj untouched.

/// Right-side panel of the expanded music view. Mirrors boring.notch's
/// CalendarView slot (`NotchHomeView.swift:447` upstream) so MusicPlayerView
/// keeps its native ~half-panel width and album art doesn't balloon to fill
/// chrome. Reads `MusicManager.shared.syncedLyrics` directly — fetching
/// lives in MusicManager.fetchLyrics, so this view is purely presentation.
struct LyricsPanel: View {
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        Group {
            if !Defaults[.enableLyrics] {
                placeholder("Lyrics disabled")
            } else if music.isFetchingLyrics {
                placeholder("Loading lyrics…")
            } else if !music.syncedLyrics.isEmpty {
                syncedView(lines: music.syncedLyrics)
            } else if !music.currentLyrics
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                plainView(text: music.currentLyrics)
            } else {
                placeholder("No lyrics found")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    @ViewBuilder
    private func placeholder(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10))
            .foregroundStyle(.secondary.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func plainView(text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func syncedView(lines: [(time: Double, text: String)]) -> some View {
        // Re-tick at ~4Hz while playing — same cadence the inline lyric
        // line in MusicControlsView uses, so highlights stay in sync
        // without spinning a Timer.
        TimelineView(.animation(minimumInterval: music.isPlaying ? 0.25 : nil)) { timeline in
            let elapsed = currentElapsed(at: timeline.date)
            let activeIdx = currentIndex(for: elapsed, in: lines) ?? -1
            let highlight = Color(nsColor: music.avgColor)
                .ensureMinimumBrightness(factor: 0.6)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: 11,
                                              weight: idx == activeIdx ? .semibold : .regular))
                                .foregroundStyle(idx == activeIdx
                                    ? highlight
                                    : .secondary.opacity(0.55))
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
    }

    /// Mirrors the elapsed-time math in `MusicControlsView.songInfo` so the
    /// active-line highlight tracks playback even while paused/seeking.
    private func currentElapsed(at date: Date) -> Double {
        guard music.isPlaying else { return music.elapsedTime }
        let delta = date.timeIntervalSince(music.timestampDate)
        let progressed = music.elapsedTime + (delta * music.playbackRate)
        return min(max(progressed, 0), music.songDuration)
    }

    private func currentIndex(for time: TimeInterval,
                              in lines: [(time: Double, text: String)]) -> Int? {
        var lo = 0, hi = lines.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return idx >= 0 ? idx : nil
    }
}
