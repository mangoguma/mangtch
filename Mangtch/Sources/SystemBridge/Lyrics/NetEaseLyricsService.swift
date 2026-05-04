import Foundation

/// NetEase Cloud Music as a fallback lyric source. Coverage for K-pop and
/// CJK catalogues is materially better than LRCLIB; in return the API is
/// unofficial and can change without notice — keep failures silent.
actor NetEaseLyricsService {
    static let shared = NetEaseLyricsService()

    private struct CacheEntry {
        let result: LyricsResult
        let savedAt: Date
    }
    private var cache: [String: CacheEntry] = [:]
    private let negativeTTL: TimeInterval = 10 * 60

    private func cacheKey(title: String, artist: String, duration: TimeInterval) -> String {
        "\(artist.lowercased())|\(title.lowercased())|\(Int(duration.rounded()))"
    }

    private func isFresh(_ entry: CacheEntry) -> Bool {
        if entry.result != .none { return true }
        return Date().timeIntervalSince(entry.savedAt) < negativeTTL
    }

    func fetch(title: String, artist: String, duration: TimeInterval) async -> LyricsResult {
        let key = cacheKey(title: title, artist: artist, duration: duration)
        if let entry = cache[key], isFresh(entry) { return entry.result }

        let queries = uniqueQueries([
            "\(title) \(artist)",
            "\(LRCLIBService.cleanTitle(title)) \(LRCLIBService.cleanArtist(artist))"
        ])
        // NetEase often hosts Chinese-translated `lrc` as the primary lyric
        // for K-pop / J-pop / Western tracks. A wrong-language lyric is
        // worse than no lyric, so we only accept a candidate whose script
        // mix is consistent with the source metadata; otherwise discard.
        let expected = expectedScripts(title: title, artist: artist)

        var result: LyricsResult = .none
        outer: for q in queries {
            let ids = await searchSongIDs(query: q, target: duration)
            for id in ids {
                let candidate = await fetchLyric(id: id)
                guard candidate != .none else { continue }
                if matchesExpectedScript(candidate, expected: expected) {
                    result = candidate
                    break outer
                }
            }
        }

        cache[key] = CacheEntry(result: result, savedAt: Date())
        return result
    }

    // MARK: - Script gating

    private struct ScriptHints: OptionSet {
        let rawValue: Int
        static let hangul = ScriptHints(rawValue: 1 << 0)
        static let kana   = ScriptHints(rawValue: 1 << 1)
        static let han    = ScriptHints(rawValue: 1 << 2)
    }

    private func expectedScripts(title: String, artist: String) -> ScriptHints {
        var hints: ScriptHints = []
        for scalar in (title + artist).unicodeScalars {
            if Self.isHangul(scalar) { hints.insert(.hangul) }
            if Self.isKana(scalar) { hints.insert(.kana) }
            if Self.isHan(scalar) { hints.insert(.han) }
        }
        return hints
    }

    /// A candidate is acceptable only when:
    /// - Hangul-source songs land Hangul-bearing lyrics
    /// - Kana-source songs land Kana-bearing lyrics
    /// - Latin-source songs (no CJK markers in metadata) don't get a
    ///   Han-dominated lyric (i.e. a Chinese cover/translation)
    private func matchesExpectedScript(_ result: LyricsResult, expected: ScriptHints) -> Bool {
        let body: String
        switch result {
        case .synced(let lines): body = lines.map(\.text).joined(separator: "\n")
        case .plain(let s): body = s
        case .none: return false
        }
        var hasHangul = false
        var hasKana = false
        var hanCount = 0
        var totalLetters = 0
        for scalar in body.unicodeScalars {
            if Self.isHangul(scalar) { hasHangul = true; totalLetters += 1; continue }
            if Self.isKana(scalar) { hasKana = true; totalLetters += 1; continue }
            if Self.isHan(scalar) { hanCount += 1; totalLetters += 1; continue }
            if Self.isLatinLetter(scalar) { totalLetters += 1 }
        }
        if expected.contains(.hangul) && !hasHangul { return false }
        if expected.contains(.kana) && !hasKana { return false }
        // Source has no CJK markers → reject Han-dominated lyric bodies.
        if !expected.contains(.han) && !expected.contains(.hangul) && !expected.contains(.kana) {
            if totalLetters > 0 && Double(hanCount) / Double(totalLetters) > 0.3 {
                return false
            }
        }
        return true
    }

    private static func isHan(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0x20000...0x2A6DF).contains(v)
            || (0xF900...0xFAFF).contains(v)
    }

    private static func isLatinLetter(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x024F).contains(v)
    }

    private static func isHangul(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0xAC00...0xD7A3).contains(v)
            || (0x1100...0x11FF).contains(v)
            || (0x3130...0x318F).contains(v)
    }

    private static func isKana(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x3040...0x309F).contains(v) || (0x30A0...0x30FF).contains(v)
    }

    private func uniqueQueries(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for q in raw {
            let trimmed = q.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed.lowercased()).inserted { out.append(trimmed) }
        }
        return out
    }

    /// Top candidates ordered by duration proximity (when known) so callers
    /// can iterate and reject lyrics whose script doesn't match the source.
    private func searchSongIDs(query: String, target: TimeInterval) async -> [Int] {
        var comps = URLComponents(string: "https://music.163.com/api/search/get")!
        comps.queryItems = [
            .init(name: "s", value: query),
            .init(name: "type", value: "1"),
            .init(name: "limit", value: "10"),
            .init(name: "offset", value: "0")
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(NESearchResponse.self, from: data)
            guard let songs = decoded.result?.songs, !songs.isEmpty else { return [] }
            // NetEase duration is in milliseconds.
            let ordered: [NESearchResponse.Song]
            if target > 1 {
                ordered = songs.sorted { lhs, rhs in
                    abs(Double(lhs.duration) / 1000 - target) < abs(Double(rhs.duration) / 1000 - target)
                }
            } else {
                ordered = songs
            }
            return ordered.prefix(5).map(\.id)
        } catch {
            return []
        }
    }

    private func fetchLyric(id: Int) async -> LyricsResult {
        var comps = URLComponents(string: "https://music.163.com/api/song/lyric")!
        comps.queryItems = [
            .init(name: "id", value: String(id)),
            .init(name: "lv", value: "1"),
            .init(name: "kv", value: "1"),
            .init(name: "tv", value: "-1")
        ]
        guard let url = comps.url else { return .none }
        var req = URLRequest(url: url)
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return .none }
            let decoded = try JSONDecoder().decode(NELyricResponse.self, from: data)
            if let raw = decoded.lrc?.lyric,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lines = LRCParser.parse(raw)
                if !lines.isEmpty { return .synced(lines) }
                return .plain(raw)
            }
            return .none
        } catch {
            return .none
        }
    }
}

private struct NESearchResponse: Decodable {
    struct Result: Decodable { let songs: [Song]? }
    struct Song: Decodable { let id: Int; let duration: Int }
    let result: Result?
}

private struct NELyricResponse: Decodable {
    struct Lyric: Decodable { let lyric: String? }
    let lrc: Lyric?
}
