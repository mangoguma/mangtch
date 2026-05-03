import Foundation
import SwiftUI

@MainActor
@Observable
final class LyricsManager {
    static let shared = LyricsManager()

    private(set) var lyrics: LyricsResult = .none
    private(set) var isLoading: Bool = false
    /// Track key currently displayed (artist|title|duration). Used by views
    /// to invalidate scroll position when the song changes.
    private(set) var currentKey: String = ""

    private var inflightKey: String?

    private init() {}

    func load(for info: MediaInfo) {
        let key = "\(info.artist.lowercased())|\(info.title.lowercased())|\(Int(info.duration.rounded()))"
        if currentKey == key && lyrics != .none { return }
        if inflightKey == key { return }

        inflightKey = key
        currentKey = key
        lyrics = .none
        isLoading = true

        Task { [weak self] in
            let result = await LRCLIBService.shared.fetch(
                title: info.title,
                artist: info.artist,
                album: info.album,
                duration: info.duration
            )
            guard let self else { return }
            // Only commit if the request is still the latest one we kicked off.
            if self.inflightKey == key {
                self.lyrics = result
                self.isLoading = false
                self.inflightKey = nil
            }
        }
    }

    func clear() {
        lyrics = .none
        isLoading = false
        currentKey = ""
        inflightKey = nil
    }

    /// Find the active line index for a given playback time. Returns nil
    /// when there are no synced lines yet (or the playhead is before the
    /// first timestamp).
    func currentLineIndex(at time: TimeInterval) -> Int? {
        guard case .synced(let lines) = lyrics, !lines.isEmpty else { return nil }
        var lo = 0
        var hi = lines.count - 1
        var idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time {
                idx = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return idx >= 0 ? idx : nil
    }
}
