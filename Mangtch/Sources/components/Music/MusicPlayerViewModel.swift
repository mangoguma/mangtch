import SwiftUI
import Combine

@Observable
@MainActor
final class MusicPlayerViewModel {
    // MARK: - State
    var nowPlaying: MediaInfo?
    var isPlaying: Bool = false
    var currentArtwork: NSImage?
    var progress: Double = 0.0 // 0.0 - 1.0
    var elapsedFormatted: String = "0:00"
    var remainingFormatted: String = "0:00"

    // Track change notification
    var showTrackChangeNotification: Bool = false
    var trackChangeInfo: MediaInfo?

    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    private var displayLinkSubscription: UUID?
    private var lastElapsed: TimeInterval = 0
    private var lastFetchTime: Date = .distantPast
    /// True while the user is dragging the progress bar; suspends
    /// time-based progress updates so the thumb stays under the cursor.
    private(set) var isScrubbing: Bool = false

    init() {}

    func startObserving() {
        // Fetch current state immediately (in case events were sent before we subscribed)
        let bridge = MusicManager.shared
        if let info = bridge.nowPlaying {
            updateNowPlaying(info)
        }
        currentArtwork = bridge.currentArtwork
        let currentPlayback = bridge.playbackState
        isPlaying = currentPlayback == .playing
        if isPlaying {
            startDisplayLink()
        }

        // Subscribe to artwork changes
        bridge.$currentArtwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                self?.currentArtwork = image
            }
            .store(in: &cancellables)

        // Subscribe to media changes
        EventBus.shared.mediaChanges
            .sink { [weak self] info in
                self?.updateNowPlaying(info)
            }
            .store(in: &cancellables)

        // Subscribe to playback state changes
        EventBus.shared.playbackChanges
            .sink { [weak self] state in
                self?.isPlaying = state == .playing
                if state == .playing {
                    self?.startDisplayLink()
                } else {
                    self?.stopDisplayLink()
                }
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        cancellables.removeAll()
        stopDisplayLink()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        MusicManager.shared.togglePlayPause()
    }

    func nextTrack() {
        MusicManager.shared.nextTrack()
    }

    func previousTrack() {
        MusicManager.shared.previousTrack()
    }

    // MARK: - Scrubbing

    /// Called continuously during a drag — updates UI labels/progress
    /// without sending AppleScript commands.
    func previewSeek(toFraction fraction: Double) {
        guard let info = nowPlaying, info.duration > 0 else { return }
        isScrubbing = true
        let f = max(0, min(1, fraction))
        let target = f * info.duration
        progress = f
        elapsedFormatted = formatTime(target)
        remainingFormatted = "-\(formatTime(info.duration - target))"
    }

    /// Called on drag end / single tap — actually moves the playhead.
    func commitSeek(toFraction fraction: Double) {
        guard let info = nowPlaying, info.duration > 0 else {
            isScrubbing = false
            return
        }
        let f = max(0, min(1, fraction))
        let target = f * info.duration
        lastElapsed = target
        lastFetchTime = Date()
        progress = f
        isScrubbing = false
        MusicManager.shared.seek(to: target)
    }

    // MARK: - Private

    private func updateNowPlaying(_ info: MediaInfo) {
        let previousTrack = nowPlaying?.title
        nowPlaying = info
        lastElapsed = info.elapsedTime
        lastFetchTime = Date()
        updateProgress()

        // Detect track change for notification (skip if panel is expanded — already visible)
        if let prev = previousTrack, prev != info.title, !info.title.isEmpty,
           NotchViewModel.shared.currentState != .expanded {
            showTrackChangeNotification = true
            trackChangeInfo = info
            // Briefly widen the right wing to exactly the title's text
            // width (NotchViewModel clamps to >= panelModeWingWidth and
            // <= maxWingWidth) so the new track fits without arbitrarily
            // overshooting to the cap.
            NotchViewModel.shared.previewWingWidth = previewWingWidth(for: info)

            // Auto-dismiss after the notification window elapses.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(AnimationTokens.trackChangeNotificationDuration * 1_000_000_000))
                showTrackChangeNotification = false
                NotchViewModel.shared.previewWingWidth = nil
            }
        }
    }

    /// Pixel width the right wing needs to render the new title + artist
    /// in full. CompactInfoView uses 11pt semibold for title, 10pt for
    /// artist, and 8pt horizontal padding on each side. We measure the
    /// wider of the two strings against AppKit's text metrics so the
    /// preview wing is sized to the actual content rather than a fixed
    /// cap. NotchViewModel clamps the result to its valid range.
    private func previewWingWidth(for info: MediaInfo) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let artistFont = NSFont.systemFont(ofSize: 10)
        let titleWidth = (info.title as NSString).size(withAttributes: [.font: titleFont]).width
        let artistWidth = (info.artist as NSString).size(withAttributes: [.font: artistFont]).width
        let textWidth = max(titleWidth, artistWidth)
        let horizontalPadding: CGFloat = 16  // matches CompactInfoView's .padding(.horizontal, 8)
        return ceil(textWidth + horizontalPadding)
    }

    private func startDisplayLink() {
        stopDisplayLink()
        displayLinkSubscription = DisplayLinkManager.shared.subscribe { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopDisplayLink() {
        if let id = displayLinkSubscription {
            DisplayLinkManager.shared.unsubscribe(id)
            displayLinkSubscription = nil
        }
    }

    private func updateProgress() {
        if isScrubbing { return }
        guard let info = nowPlaying, info.duration > 0 else {
            progress = 0
            elapsedFormatted = "0:00"
            remainingFormatted = "0:00"
            return
        }

        // Estimate current elapsed time based on last known position + time since fetch
        var currentElapsed = lastElapsed
        if isPlaying {
            currentElapsed += Date().timeIntervalSince(lastFetchTime)
        }
        currentElapsed = min(currentElapsed, info.duration)

        progress = currentElapsed / info.duration
        elapsedFormatted = formatTime(currentElapsed)
        remainingFormatted = "-\(formatTime(info.duration - currentElapsed))"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
