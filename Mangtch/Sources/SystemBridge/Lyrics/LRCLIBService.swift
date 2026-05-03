import Foundation

struct LRCLine: Equatable {
    let time: TimeInterval
    let text: String
}

enum LyricsResult: Equatable {
    case synced([LRCLine])
    case plain(String)
    case none
}

/// Free, key-less lyrics provider (https://lrclib.net).
/// Synced LRC when available, plain text otherwise.
actor LRCLIBService {
    static let shared = LRCLIBService()
    private var cache: [String: LyricsResult] = [:]

    private func cacheKey(title: String, artist: String, duration: TimeInterval) -> String {
        "\(artist.lowercased())|\(title.lowercased())|\(Int(duration.rounded()))"
    }

    func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsResult {
        let key = cacheKey(title: title, artist: artist, duration: duration)
        if let cached = cache[key] { return cached }

        let result = await query(title: title, artist: artist, album: album, duration: duration)
        cache[key] = result
        return result
    }

    private func query(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsResult {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = [
            .init(name: "artist_name", value: artist),
            .init(name: "track_name", value: title),
            .init(name: "duration", value: String(Int(duration.rounded())))
        ]
        if !album.isEmpty {
            items.append(.init(name: "album_name", value: album))
        }
        comps.queryItems = items
        guard let url = comps.url else { return .none }

        var req = URLRequest(url: url)
        req.setValue("Mangtch (https://github.com/mangoguma/mangtch)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
                // Fall through to /api/search as a relaxed match.
                return await search(title: title, artist: artist)
            }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return .none
            }
            let decoded = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            return decoded.toResult()
        } catch {
            return .none
        }
    }

    private func search(title: String, artist: String) async -> LyricsResult {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist)
        ]
        guard let url = comps.url else { return .none }
        var req = URLRequest(url: url)
        req.setValue("Mangtch (https://github.com/mangoguma/mangtch)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let arr = try JSONDecoder().decode([LRCLIBResponse].self, from: data)
            // Prefer synced; fall back to first plain.
            if let synced = arr.first(where: { ($0.syncedLyrics ?? "").isEmpty == false }) {
                return synced.toResult()
            }
            return arr.first?.toResult() ?? .none
        } catch {
            return .none
        }
    }
}

private struct LRCLIBResponse: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?

    func toResult() -> LyricsResult {
        if let s = syncedLyrics, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .synced(LRCParser.parse(s))
        }
        if let p = plainLyrics, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .plain(p)
        }
        return .none
    }
}

enum LRCParser {
    /// Parse LRC. Each line may have multiple timestamps; emit a separate
    /// LRCLine for each, sharing the trailing text. Tag-only lines (e.g.
    /// `[ar:...]`, `[ti:...]`) are skipped because they have no text body.
    static func parse(_ raw: String) -> [LRCLine] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[\.:]\d+)?)\]"#) else {
            return []
        }
        var out: [LRCLine] = []
        for rawLine in raw.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.upperBound)
                .trimmingCharacters(in: .whitespaces)
            for m in matches {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ssRaw = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")
                let ss = Double(ssRaw) ?? 0
                out.append(LRCLine(time: mm * 60 + ss, text: text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }
}
