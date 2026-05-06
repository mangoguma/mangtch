import Foundation

/// One row of the schedule API. We decode only the fields we actually use —
/// the Naver Sports endpoint isn't a documented contract, so a minimal
/// surface area lets the widget keep working when other fields drift.
struct KBOGame: Decodable, Identifiable, Equatable, Hashable {
    let gameId: String
    let gameDateTime: String          // "2025-05-01T18:30:00"
    let homeTeamCode: String          // "HH"
    let homeTeamName: String          // "한화"
    let homeTeamScore: Int
    let homeTeamEmblemUrl: String?    // optional — Naver sometimes omits
    let awayTeamCode: String
    let awayTeamName: String
    let awayTeamScore: Int
    let awayTeamEmblemUrl: String?
    let statusCode: String            // "BEFORE" / "STARTED" / "RESULT"
    let statusInfo: String            // "경기취소" / "8회초" / etc.
    let cancel: Bool
    let suspended: Bool

    var homeEmblemURL: URL? { homeTeamEmblemUrl.flatMap(URL.init(string:)) }
    var awayEmblemURL: URL? { awayTeamEmblemUrl.flatMap(URL.init(string:)) }

    /// True only when the game has a clear winner. We use this to dim the
    /// loser's score in the row layout.
    var winnerSide: Side? {
        guard isFinished, homeTeamScore != awayTeamScore else { return nil }
        return homeTeamScore > awayTeamScore ? .home : .away
    }

    enum Side { case home, away }

    var id: String { gameId }

    /// True while the game is actively being played (Naver uses STARTED for
    /// in-progress; we treat the typo-defensive PROGRESS as live too).
    var isLive: Bool {
        guard !cancel, !suspended else { return false }
        return statusCode == "STARTED" || statusCode == "PROGRESS"
    }

    var isFinished: Bool {
        statusCode == "RESULT" || statusCode == "ENDED"
    }

    var isScheduled: Bool {
        statusCode == "BEFORE" && !cancel
    }

    /// Local "HH:mm" of the scheduled first pitch. Falls back to the raw
    /// timestamp tail if parsing fails.
    var startTimeText: String {
        let parsed = ISO8601DateFormatter.kboLocal.date(from: gameDateTime + "+0900")
        guard let parsed else {
            return String(gameDateTime.suffix(5))
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: parsed)
    }
}

/// Top-level Naver Sports schedule response.
struct KBOScheduleResponse: Decodable {
    struct Result: Decodable {
        let games: [KBOGame]
    }
    let result: Result
}

private extension ISO8601DateFormatter {
    /// Naver returns naive local timestamps. We append a Korean offset and
    /// parse with this strict formatter so DST quirks don't bite.
    static let kboLocal: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        return f
    }()
}
