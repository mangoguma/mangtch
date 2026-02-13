import Foundation
import Combine
import AppKit

// MARK: - Event Types

enum HUDType: Equatable {
    case volume
    case brightness
    case keyboardBacklight
}

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

    // HUD
    case hudTriggered(HUDType, Float)

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

    /// Subscribe to HUD triggers only
    var hudTriggers: AnyPublisher<(HUDType, Float), Never> {
        on { event in
            if case .hudTriggered(let type, let value) = event { return (type, value) }
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
