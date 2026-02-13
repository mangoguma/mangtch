import Foundation
import AppKit
import SwiftUI
import Combine

// MARK: - Active Player

enum ActivePlayer: String {
    case spotify = "com.spotify.client"
    case appleMusic = "com.apple.Music"
}

// MARK: - MediaBridge

@MainActor
final class MediaBridge: ObservableObject {
    static let shared = MediaBridge()

    // MARK: - Published State

    @Published private(set) var nowPlaying: MediaInfo?
    @Published private(set) var playbackState: PlaybackState = .stopped
    @Published private(set) var isAvailable: Bool = true
    @Published private(set) var activePlayer: ActivePlayer?
    @Published private(set) var isLiked: Bool = false

    // MARK: - Artwork (Single Source of Truth)

    @Published private(set) var currentArtwork: NSImage?
    @Published private(set) var dominantColor: Color = .clear
    @Published private(set) var secondaryColor: Color = .clear

    // MARK: - Private

    private var pollingTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let artworkCache = NSCache<NSString, NSImage>()
    private var artworkFetchTask: URLSessionDataTask?
    private var lastArtworkCacheKey: String = ""

    // Dedicated URLSession with caching for fast artwork loading
    private lazy var artworkSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 5
        config.networkServiceType = .responsiveData
        return URLSession(configuration: config)
    }()

    // MARK: - Initialization

    private init() {
        artworkCache.countLimit = 30
    }

    // MARK: - Public API

    func startMonitoring() {
        NSLog("[MediaBridge] ===== startMonitoring() (AppleScript mode) =====")

        // Detect active player immediately
        detectActivePlayer()

        // Start polling timer (2 second interval, like SpotMenu)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollNowPlaying()
            }
        }

        // Also run immediately
        pollNowPlaying()

        // Observe app launches/terminations for auto-switching
        let ws = NSWorkspace.shared.notificationCenter

        let launchObserver = ws.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                let bundleId = app.bundleIdentifier ?? ""
                if bundleId == ActivePlayer.spotify.rawValue || bundleId == ActivePlayer.appleMusic.rawValue {
                    NSLog("[MediaBridge] Music app launched: \(bundleId)")
                    Task { @MainActor in
                        self?.detectActivePlayer()
                        self?.pollNowPlaying()
                    }
                }
            }
        }
        workspaceObservers.append(launchObserver)

        let terminateObserver = ws.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                let bundleId = app.bundleIdentifier ?? ""
                if bundleId == ActivePlayer.spotify.rawValue || bundleId == ActivePlayer.appleMusic.rawValue {
                    NSLog("[MediaBridge] Music app terminated: \(bundleId)")
                    Task { @MainActor in
                        self?.detectActivePlayer()
                        // Clear now playing if the terminated app was the active player
                        if self?.activePlayer == nil {
                            self?.nowPlaying = nil
                            self?.playbackState = .stopped
                            EventBus.shared.send(.playbackStateChanged(.stopped))
                        }
                    }
                }
            }
        }
        workspaceObservers.append(terminateObserver)

        NSLog("[MediaBridge] Monitoring started with 2s polling + workspace observers")
    }

    func stopMonitoring() {
        NSLog("[MediaBridge] Stopping monitoring")
        pollingTimer?.invalidate()
        pollingTimer = nil
        artworkFetchTask?.cancel()
        artworkFetchTask = nil

        let ws = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            ws.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        guard let player = activePlayer else { return }
        switch player {
        case .spotify:
            runAppleScript("tell application \"Spotify\" to playpause")
        case .appleMusic:
            if playbackState == .playing {
                runAppleScript("tell application \"Music\" to pause")
            } else {
                runAppleScript("tell application \"Music\" to play")
            }
        }
        // Quick state toggle for responsive UI, then poll to confirm
        let newState: PlaybackState = playbackState == .playing ? .paused : .playing
        playbackState = newState
        EventBus.shared.send(.playbackStateChanged(newState))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pollNowPlaying()
        }
    }

    func play() {
        guard let player = activePlayer else { return }
        switch player {
        case .spotify:
            runAppleScript("tell application \"Spotify\" to play")
        case .appleMusic:
            runAppleScript("tell application \"Music\" to play")
        }
    }

    func pause() {
        guard let player = activePlayer else { return }
        switch player {
        case .spotify:
            runAppleScript("tell application \"Spotify\" to pause")
        case .appleMusic:
            runAppleScript("tell application \"Music\" to pause")
        }
    }

    func nextTrack() {
        guard let player = activePlayer else { return }
        switch player {
        case .spotify:
            runAppleScript("tell application \"Spotify\" to next track")
        case .appleMusic:
            runAppleScript("tell application \"Music\" to next track")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pollNowPlaying()
        }
    }

    func previousTrack() {
        guard let player = activePlayer else { return }
        switch player {
        case .spotify:
            runAppleScript("tell application \"Spotify\" to previous track")
        case .appleMusic:
            runAppleScript("tell application \"Music\" to previous track")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pollNowPlaying()
        }
    }

    func toggleLike() {
        guard let player = activePlayer else { return }
        let newLiked = !isLiked

        switch player {
        case .spotify:
            // Spotify: use starred property
            let starredValue = newLiked ? "true" : "false"
            runAppleScript("tell application \"Spotify\" to set starred of current track to \(starredValue)")
        case .appleMusic:
            // Apple Music: use favorited property
            let favValue = newLiked ? "true" : "false"
            runAppleScript("tell application \"Music\" to set favorited of current track to \(favValue)")
        }

        // Optimistic update
        isLiked = newLiked
    }

    private func checkLikeStatus() {
        guard let player = activePlayer else { return }

        switch player {
        case .spotify:
            if let result = runAppleScript("tell application \"Spotify\" to return starred of current track") {
                isLiked = result.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
            }
        case .appleMusic:
            if let result = runAppleScript("tell application \"Music\" to return favorited of current track") {
                isLiked = result.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
            }
        }
    }

    // MARK: - Private: Player Detection

    private func detectActivePlayer() {
        let spotifyRunning = isAppRunning(ActivePlayer.spotify.rawValue)
        let appleMusicRunning = isAppRunning(ActivePlayer.appleMusic.rawValue)

        if spotifyRunning {
            activePlayer = .spotify
        } else if appleMusicRunning {
            activePlayer = .appleMusic
        } else {
            activePlayer = nil
        }

        NSLog("[MediaBridge] Active player: \(activePlayer?.rawValue ?? "none") (Spotify=\(spotifyRunning), Music=\(appleMusicRunning))")
    }

    private func isAppRunning(_ bundleId: String) -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    // MARK: - Private: Polling

    private func pollNowPlaying() {
        // Re-detect if no active player
        if activePlayer == nil {
            detectActivePlayer()
        }

        guard let player = activePlayer else { return }

        switch player {
        case .spotify:
            fetchSpotifyInfo()
        case .appleMusic:
            fetchAppleMusicInfo()
        }
    }

    // MARK: - Private: Spotify (AppleScript)

    private func fetchSpotifyInfo() {
        let script = """
            tell application "Spotify"
                if it is running then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set albumName to album of current track
                    set artworkUrl to artwork url of current track
                    set durationMs to duration of current track
                    set currentSec to player position
                    set isPlayingState to (player state is playing)
                    return trackName & "|||" & artistName & "|||" & albumName & "|||" & artworkUrl & "|||" & durationMs & "|||" & currentSec & "|||" & isPlayingState
                else
                    return "NOT_RUNNING"
                end if
            end tell
        """

        guard let output = runAppleScript(script), output != "NOT_RUNNING" else {
            // Spotify stopped while we thought it was running
            if activePlayer == .spotify {
                activePlayer = nil
                detectActivePlayer()
            }
            return
        }

        let parts = output.components(separatedBy: "|||")
        guard parts.count == 7 else {
            NSLog("[MediaBridge] Spotify: unexpected parts count: \(parts.count)")
            return
        }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let artworkURLStr = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let durationMs = Double(parts[4].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1000
        let currentSec = Double(parts[5].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) ?? 0
        let isPlaying = parts[6].trimmingCharacters(in: .whitespacesAndNewlines) == "true"

        let duration = durationMs / 1000.0
        let elapsed = min(currentSec, duration)
        let artworkURL = URL(string: artworkURLStr)

        // Artwork: check cache or fetch from URL
        let cacheKey = "\(artist)-\(album)" as NSString
        let cachedArtwork = artworkCache.object(forKey: cacheKey)

        if cachedArtwork != nil {
            setArtwork(cachedArtwork)
        } else if let url = artworkURL {
            fetchArtworkFromURL(url, cacheKey: cacheKey)
        }

        let mediaInfo = MediaInfo(
            title: title,
            artist: artist,
            album: album,
            artwork: nil,
            artworkURL: artworkURL,
            duration: duration,
            elapsedTime: elapsed,
            appBundleIdentifier: ActivePlayer.spotify.rawValue
        )

        updateState(mediaInfo: mediaInfo, isPlaying: isPlaying)
    }

    // MARK: - Private: Apple Music (AppleScript)

    private func fetchAppleMusicInfo() {
        let script = """
            tell application "Music"
                if it is running then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set albumName to album of current track
                    set durationSec to duration of current track
                    set currentSec to player position
                    set isPlayingState to (player state is playing)
                    return trackName & "|||" & artistName & "|||" & albumName & "|||" & durationSec & "|||" & currentSec & "|||" & isPlayingState
                else
                    return "NOT_RUNNING"
                end if
            end tell
        """

        guard let output = runAppleScript(script), output != "NOT_RUNNING" else {
            if activePlayer == .appleMusic {
                activePlayer = nil
                detectActivePlayer()
            }
            return
        }

        let parts = output.components(separatedBy: "|||")
        guard parts.count == 6 else {
            NSLog("[MediaBridge] Music: unexpected parts count: \(parts.count)")
            return
        }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = Double(parts[3].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) ?? 1
        let currentSec = Double(parts[4].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) ?? 0
        let isPlaying = parts[5].trimmingCharacters(in: .whitespacesAndNewlines) == "true"

        let elapsed = min(currentSec, duration)

        // Artwork: fetch via AppleScript data
        let cacheKey = "\(artist)-\(album)" as NSString
        var artwork = artworkCache.object(forKey: cacheKey)

        if artwork == nil {
            artwork = fetchAppleMusicArtwork()
            if let artwork {
                artworkCache.setObject(artwork, forKey: cacheKey)
            }
        }

        setArtwork(artwork)

        let mediaInfo = MediaInfo(
            title: title,
            artist: artist,
            album: album,
            artwork: nil,
            artworkURL: nil,
            duration: duration,
            elapsedTime: elapsed,
            appBundleIdentifier: ActivePlayer.appleMusic.rawValue
        )

        updateState(mediaInfo: mediaInfo, isPlaying: isPlaying)
    }

    private func fetchAppleMusicArtwork() -> NSImage? {
        let script = """
            tell application "Music"
                if it is running then
                    get data of artwork 1 of current track
                end if
            end tell
        """

        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else { return nil }
        let output = scriptObject.executeAndReturnError(&error)
        let data = output.data
        return NSImage(data: data)
    }

    // MARK: - Private: Artwork URL Fetch

    private func fetchArtworkFromURL(_ url: URL, cacheKey: NSString) {
        // Don't re-fetch the same artwork
        let cacheKeyStr = cacheKey as String
        guard cacheKeyStr != lastArtworkCacheKey else { return }
        lastArtworkCacheKey = cacheKeyStr

        // Clear artwork immediately so views show placeholder
        currentArtwork = nil

        // Optimize Spotify artwork URL: request 300x300 instead of 640x640
        let optimizedURL = optimizeSpotifyArtworkURL(url)

        artworkFetchTask?.cancel()
        var request = URLRequest(url: optimizedURL)
        request.cachePolicy = .returnCacheDataElseLoad

        artworkFetchTask = artworkSession.dataTask(with: request) { [weak self] data, _, error in
            guard let data, error == nil, let image = NSImage(data: data) else { return }

            Task { @MainActor in
                guard let self else { return }
                self.artworkCache.setObject(image, forKey: cacheKey)
                self.setArtwork(image)
            }
        }
        artworkFetchTask?.priority = 1.0  // Highest priority
        artworkFetchTask?.resume()
    }

    /// Rewrite Spotify CDN URLs to request 300x300 instead of 640x640
    private func optimizeSpotifyArtworkURL(_ url: URL) -> URL {
        // Spotify artwork URLs: https://i.scdn.co/image/ab67616d0000b273...
        // b273 = 640x640, 4851 = 300x300, 1e02 = 64x64
        let str = url.absoluteString
        if str.contains("i.scdn.co/image/ab67616d0000b273") {
            let optimized = str.replacingOccurrences(of: "ab67616d0000b273", with: "ab67616d00004851")
            return URL(string: optimized) ?? url
        }
        return url
    }

    // MARK: - Private: Artwork Single Source of Truth

    private func setArtwork(_ image: NSImage?) {
        guard currentArtwork !== image else { return }  // Same instance, skip
        currentArtwork = image
        extractColors(from: image)
    }

    private func extractColors(from image: NSImage?) {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            withAnimation(.easeInOut(duration: 0.5)) {
                dominantColor = .clear
                secondaryColor = .clear
            }
            return
        }

        let width = 8, height = 8
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [(r: CGFloat, g: CGFloat, b: CGFloat, sat: CGFloat)] = []
        for i in 0..<(width * height) {
            let offset = i * 4
            let r = CGFloat(pixelData[offset]) / 255.0
            let g = CGFloat(pixelData[offset + 1]) / 255.0
            let b = CGFloat(pixelData[offset + 2]) / 255.0
            let maxC = max(r, g, b), minC = min(r, g, b)
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0
            if maxC > 0.15 && maxC < 0.9 && sat > 0.1 {
                buckets.append((r, g, b, sat))
            }
        }
        buckets.sort { $0.sat > $1.sat }

        withAnimation(.easeInOut(duration: 0.5)) {
            if let p = buckets.first {
                dominantColor = Color(red: p.r, green: p.g, blue: p.b)
            } else {
                dominantColor = .blue
            }
            if buckets.count > buckets.count / 3,
               let s = buckets.dropFirst(buckets.count / 3).first {
                secondaryColor = Color(red: s.r, green: s.g, blue: s.b)
            } else {
                secondaryColor = dominantColor
            }
        }
    }

    // MARK: - Private: State Update

    private func updateState(mediaInfo: MediaInfo, isPlaying: Bool) {
        let newPlaybackState: PlaybackState = isPlaying ? .playing : .paused

        if playbackState != newPlaybackState {
            playbackState = newPlaybackState
            EventBus.shared.send(.playbackStateChanged(newPlaybackState))
        }

        if nowPlaying != mediaInfo {
            nowPlaying = mediaInfo
            EventBus.shared.send(.mediaChanged(mediaInfo))
            checkLikeStatus()
        } else if let current = nowPlaying, current.elapsedTime != mediaInfo.elapsedTime {
            nowPlaying = mediaInfo
            EventBus.shared.send(.mediaChanged(mediaInfo))
        }
    }

    // MARK: - Private: AppleScript Helper

    @discardableResult
    private func runAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else { return nil }
        let output = scriptObject.executeAndReturnError(&error)
        if let error {
            // Don't log for "not running" type errors - they're expected
            let errorNum = error["NSAppleScriptErrorNumber"] as? Int ?? 0
            if errorNum != -600 && errorNum != -1728 {
                NSLog("[MediaBridge] AppleScript error: \(error)")
            }
        }
        return output.stringValue
    }
}
