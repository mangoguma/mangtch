import Foundation

/// Per-game inning-by-inning detail. Sourced from KBO's official site
/// (koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll), since Naver's
/// schedule endpoint only returns final scores. The two sources are
/// stitched together by gameId in the ViewModel.
struct KBOLinescore: Equatable {
    let stadium: String              // "잠실"
    let crowd: String                // "19,883"
    let startTime: String            // "18:32"
    let endTime: String              // "22:11"
    let runTime: String              // "3:39"

    /// Innings actually played (1...N). Excludes the trailing "—" cells
    /// for innings that didn't happen.
    let innings: Int

    /// Per-inning runs for away/home. Length matches `innings`. Empty when
    /// KBO's official scorekeeping hasn't ingested the game yet (live
    /// games often run 1–2 innings ahead of their site's boxscore).
    let awayInningScores: [String]
    let homeInningScores: [String]

    /// R / H / E / B totals (away first, home second). Nil while the
    /// boxscore tables are absent.
    let awayTotals: Totals?
    let homeTotals: Totals?

    /// True only when KBO has actually populated the inning grid. Drives
    /// the detail view's choice between rendering the full grid and a
    /// "data is being prepared" placeholder.
    var hasInningData: Bool {
        !awayInningScores.isEmpty && awayTotals != nil
    }

    let awayTeamName: String         // "KT"
    let homeTeamName: String         // "두산"

    struct Totals: Equatable {
        let runs: Int
        let hits: Int
        let errors: Int
        let walks: Int
    }
}

extension KBOLinescore {
    /// Decode Naver's `/schedule/games/{id}/relay` response shape.
    /// inningScore.{home,away} is a `{"1":"0","2":"0","3":"-",...}` map of
    /// inning → runs (or "-" for unplayed); currentGameState carries the
    /// running R/H/E/B totals. Updates within seconds of each play.
    init?(naverRelay raw: Data) {
        struct Outer: Decodable {
            struct Result: Decodable { let textRelayData: TextRelay? }
            let result: Result?
        }
        struct TextRelay: Decodable {
            let inningScore: InningScore?
            let currentGameState: CurrentGameState?
        }
        struct InningScore: Decodable {
            let home: [String: String]?
            let away: [String: String]?
        }
        struct CurrentGameState: Decodable {
            let homeScore, awayScore: String?
            let homeHit, awayHit: String?
            let homeError, awayError: String?
            let homeBallFour, awayBallFour: String?
        }

        guard let outer = try? JSONDecoder().decode(Outer.self, from: raw),
              let trd = outer.result?.textRelayData
        else { return nil }

        // Header fields aren't in the relay payload — leave empty so the
        // view falls back to whatever the schedule API already showed
        // (game.statusInfo, etc.) without crashing.
        self.stadium = ""
        self.crowd = ""
        self.startTime = ""
        self.endTime = ""
        self.runTime = ""
        self.awayTeamName = ""
        self.homeTeamName = ""

        if let score = trd.inningScore,
           let homeMap = score.home, let awayMap = score.away,
           !homeMap.isEmpty || !awayMap.isEmpty {
            // Sort inning keys numerically; pad to 9 so empty late innings
            // still render as "-".
            let played = max(
                Self.maxKey(homeMap),
                Self.maxKey(awayMap)
            )
            let count = max(played, 9)
            self.innings = count
            self.homeInningScores = (1...count).map { i in homeMap["\(i)"] ?? "-" }
            self.awayInningScores = (1...count).map { i in awayMap["\(i)"] ?? "-" }

            if let cgs = trd.currentGameState {
                self.awayTotals = Totals(
                    runs: Int(cgs.awayScore ?? "") ?? 0,
                    hits: Int(cgs.awayHit ?? "") ?? 0,
                    errors: Int(cgs.awayError ?? "") ?? 0,
                    walks: Int(cgs.awayBallFour ?? "") ?? 0
                )
                self.homeTotals = Totals(
                    runs: Int(cgs.homeScore ?? "") ?? 0,
                    hits: Int(cgs.homeHit ?? "") ?? 0,
                    errors: Int(cgs.homeError ?? "") ?? 0,
                    walks: Int(cgs.homeBallFour ?? "") ?? 0
                )
            } else {
                self.awayTotals = nil
                self.homeTotals = nil
            }
        } else {
            self.innings = 9
            self.awayInningScores = []
            self.homeInningScores = []
            self.awayTotals = nil
            self.homeTotals = nil
        }
    }

    private static func maxKey(_ dict: [String: String]) -> Int {
        dict.keys.compactMap(Int.init).max() ?? 0
    }
}

