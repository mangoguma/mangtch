import Foundation
import Combine
import AppKit

// MARK: - Event Types

enum PlaybackState: Equatable {
    case playing
    case paused
    case stopped
}

struct MediaInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: NSImage?
    let artworkURL: URL?
    let duration: TimeInterval
    let elapsedTime: TimeInterval
    let appBundleIdentifier: String?
    /// Spotify track ID (e.g. "3n3Ppam7vgaVa1iaRUc9Lp"), nil for Apple Music.
    /// Used by SpotifyAPI for liked-status checks.
    let trackID: String?

    init(
        title: String,
        artist: String,
        album: String,
        artwork: NSImage?,
        artworkURL: URL?,
        duration: TimeInterval,
        elapsedTime: TimeInterval,
        appBundleIdentifier: String?,
        trackID: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.artworkURL = artworkURL
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.appBundleIdentifier = appBundleIdentifier
        self.trackID = trackID
    }

    static func == (lhs: MediaInfo, rhs: MediaInfo) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.album == rhs.album && lhs.duration == rhs.duration
    }
}

enum NotchState: Equatable {
    case idle
    case hovering
    case expanded
}

enum NotchEvent {
    // Panel state
    case stateChanged(NotchState)

    // Media
    case mediaChanged(MediaInfo)
    case playbackStateChanged(PlaybackState)

    // File shelf
    case fileDropped(URL)
    case fileRemoved(UUID)

    // Settings
    case settingsChanged(String)

    // System
    case screenChanged
}

// MARK: - EventBus

final class EventBus: @unchecked Sendable {
    static let shared = EventBus()

    private let subject = PassthroughSubject<NotchEvent, Never>()

    var publisher: AnyPublisher<NotchEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    func send(_ event: NotchEvent) {
        subject.send(event)
    }

    /// Convenience: filter and map events by type
    func on<T>(_ extract: @escaping (NotchEvent) -> T?) -> AnyPublisher<T, Never> {
        subject
            .compactMap(extract)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Subscribe to state changes only
    var stateChanges: AnyPublisher<NotchState, Never> {
        on { event in
            if case .stateChanged(let state) = event { return state }
            return nil
        }
    }

    /// Subscribe to media changes only
    var mediaChanges: AnyPublisher<MediaInfo, Never> {
        on { event in
            if case .mediaChanged(let info) = event { return info }
            return nil
        }
    }

    /// Subscribe to playback state changes only
    var playbackChanges: AnyPublisher<PlaybackState, Never> {
        on { event in
            if case .playbackStateChanged(let state) = event { return state }
            return nil
        }
    }

    private init() {}
}
