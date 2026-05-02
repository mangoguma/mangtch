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

    init() {}

    func startObserving() {
        // Fetch current state immediately (in case events were sent before we subscribed)
        let bridge = MediaBridge.shared
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
        MediaBridge.shared.togglePlayPause()
    }

    func nextTrack() {
        MediaBridge.shared.nextTrack()
    }

    func previousTrack() {
        MediaBridge.shared.previousTrack()
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

            // Auto-dismiss after 3 seconds
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(AnimationTokens.trackChangeNotificationDuration * 1_000_000_000))
                showTrackChangeNotification = false
            }
        }
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
