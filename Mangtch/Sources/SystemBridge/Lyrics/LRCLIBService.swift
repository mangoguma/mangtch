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

    private struct CacheEntry {
        let result: LyricsResult
        let savedAt: Date
    }
    private var cache: [String: CacheEntry] = [:]
    /// Negative results expire so a transient outage or bad metadata pass
    /// doesn't pin "No lyrics found" until app restart.
    private let negativeTTL: TimeInterval = 10 * 60

    private func cacheKey(title: String, artist: String, duration: TimeInterval) -> String {
        "\(artist.lowercased())|\(title.lowercased())|\(Int(duration.rounded()))"
    }

    private func isFresh(_ entry: CacheEntry) -> Bool {
        if entry.result != .none { return true }
        return Date().timeIntervalSince(entry.savedAt) < negativeTTL
    }

    func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsResult {
        let key = cacheKey(title: title, artist: artist, duration: duration)
        if let entry = cache[key], isFresh(entry) { return entry.result }

        let variants = queryVariants(title: title, artist: artist)

        var result: LyricsResult = .none
        // Pass 1: exact /get with each (title, artist) variant.
        for (t, a) in variants {
            result = await tryGet(title: t, artist: a, album: album, duration: duration)
            if result != .none { break }
        }
        // Pass 2: relaxed /search if /get came up empty for every variant.
        if result == .none {
            for (t, a) in variants {
                result = await search(title: t, artist: a, duration: duration)
                if result != .none { break }
            }
        }

        cache[key] = CacheEntry(result: result, savedAt: Date())
        return result
    }

    private func queryVariants(title: String, artist: String) -> [(String, String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for pair in [(title, artist), (Self.cleanTitle(title), Self.cleanArtist(artist))] {
            let t = pair.0.trimmingCharacters(in: .whitespaces)
            let a = pair.1.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !a.isEmpty else { continue }
            let key = "\(t.lowercased())|\(a.lowercased())"
            if seen.insert(key).inserted { out.append((t, a)) }
        }
        return out
    }

    private func tryGet(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsResult {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = [
            .init(name: "artist_name", value: artist),
            .init(name: "track_name", value: title)
        ]
        // Duration is the strict matcher on /get — only send it when we
        // actually have a believable value, otherwise we're guaranteed a 404.
        if duration > 1 {
            items.append(.init(name: "duration", value: String(Int(duration.rounded()))))
        }
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
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return .none
            }
            let decoded = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            return decoded.toResult()
        } catch {
            return .none
        }
    }

    private func search(title: String, artist: String, duration: TimeInterval) async -> LyricsResult {
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
            guard !arr.isEmpty else { return .none }

            // Prefer synced; among candidates pick the entry whose duration
            // is closest to ours so K-pop "동명이곡" mismatches drop out.
            let synced = arr.filter { ($0.syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            let pool = synced.isEmpty ? arr : synced
            let best = pool.min { lhs, rhs in
                Self.durationDistance(lhs.duration, target: duration) < Self.durationDistance(rhs.duration, target: duration)
            }
            return best?.toResult() ?? .none
        } catch {
            return .none
        }
    }

    private static func durationDistance(_ candidate: Double?, target: TimeInterval) -> Double {
        guard let c = candidate, target > 0 else { return .greatestFiniteMagnitude }
        return abs(c - target)
    }

    // MARK: - Normalization

    /// Strip release-cruft that LRCLIB rarely indexes verbatim:
    /// "(feat. X)", "[Live]", "- 2009 Remaster", " - Single Version".
    static func cleanTitle(_ raw: String) -> String {
        var s = raw
        let patterns = [
            #"\s*[\(\[][^\)\]]*[\)\]]"#,
            #"\s*-\s*\d{4}\s*Remaster(?:ed)?(?:\s+Version)?$"#,
            #"\s*-\s*Remaster(?:ed)?(?:\s+\d{4})?$"#,
            #"\s*-\s*Single Version$"#,
            #"\s*-\s*Live(?:\s+at[^$]*)?$"#,
            #"\s*-\s*Mono(?:\s+Version)?$"#,
            #"\s*-\s*Stereo(?:\s+Version)?$"#,
            #"\s*-\s*Deluxe(?:\s+Edition)?$"#,
            #"\s*-\s*Bonus Track$"#
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive) else { continue }
            let ns = s as NSString
            s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Take the primary artist — drop everyone after a featuring/collab
    /// joiner. LRCLIB indexes by primary artist most of the time.
    static func cleanArtist(_ raw: String) -> String {
        let separators = [" feat. ", " feat ", " ft. ", " ft ", " featuring ", ", ", " & ", " x ", " X ", " with "]
        var s = raw
        for sep in separators {
            if let r = s.range(of: sep, options: .caseInsensitive) {
                s = String(s[..<r.lowerBound])
                break
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

private struct LRCLIBResponse: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?
    let duration: Double?

    func toResult() -> LyricsResult {
        if let s = syncedLyrics, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = LRCParser.parse(s)
            if !lines.isEmpty { return .synced(lines) }
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
