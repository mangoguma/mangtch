import Foundation

/// Cached starting-pitcher pair per game. Lifted out of `KBOLinescore` so
/// the collapsed game row can show starters from a lightweight cache
/// instead of holding the full inning grid in memory for every game.
struct KBOStarters: Equatable, Hashable {
    let away: String?
    let home: String?

    var hasAny: Bool { away != nil || home != nil }
}

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

    /// Starting pitcher names per side. Resolved as the first entry in each
    /// lineup's `pitcher` array (KBO's relay payload lists the starter first
    /// and appends relievers as they enter). nil pre-game when lineups
    /// haven't been published yet, or when the response omitted the lineup.
    let awayStartingPitcher: String?
    let homeStartingPitcher: String?

    /// Most recent play description from the text-relay feed, e.g.
    /// "강민호 : 좌익수 앞 1루타". nil for games without a play stream
    /// (pre-game / cancelled). Used to drive a ticker on the right wing.
    let latestPlay: Play?

    /// Every play in the text-relay feed, sorted by seqno ascending.
    /// The ViewModel diffs this against its last-seen seqno to enqueue
    /// only the genuinely new plays and ticker them one at a time, instead
    /// of skipping straight to the most recent line.
    let allPlays: [Play]

    /// Current inning number and half ("0"=top/away, "1"=bottom/home).
    /// Used to detect inning transitions and backfill missed plays.
    let currentInning: Int
    let currentHomeOrAway: String  // "0" or "1"

    /// At-bat snapshot: count, outs, runners on base. nil for non-live or
    /// pre-game states where currentGameState is empty.
    let liveState: LiveState?

    struct Totals: Equatable {
        let runs: Int
        let hits: Int
        let errors: Int
        let walks: Int
    }

    struct Play: Equatable {
        let seqno: Int
        let inning: Int
        let text: String
        let attackingSide: AttackingSide?
        /// Raw Naver type integer for sound effect mapping.
        let naverType: Int
        /// Editorial weight for this play, derived from Naver's `type`
        /// integer. Lets the ticker drop pitch-by-pitch noise from the
        /// queue while still surfacing scoring/at-bat outcomes, and lets
        /// TTS speak only the genuinely worth-narrating events.
        let importance: Importance

        enum AttackingSide: Equatable {
            case home
            case away
        }

        /// Naver `textOption.type` taxonomy observed live:
        ///   0  이닝 시작 헤더 ("7회초 KT 공격")
        ///   1  매 투구 ("1구 스트라이크")                  → low
        ///   2  교체 / 수비위치 변경                          → medium
        ///   7  투수 동작 (예: "투수 투수판 이탈")             → medium
        ///   8  타자 등장 ("5번타자 김민석")                   → medium
        ///   13 타석 결과 ("…삼진 아웃" / "…1루타" / "볼넷")    → high
        ///   14 주루 (도루/진루/포스아웃)                      → high
        ///   23 안타 (드물게, 13과 별도 라인)                  → high
        ///   24 홈인 (득점)                                    → critical
        ///   99 구분선/엔딩 ("=====", "승리투수: …")           → 필터
        enum Importance: Int, Comparable, Equatable {
            case low = 0      // per-pitch chatter
            case medium = 1   // metadata: inning, batter intro, sub
            case high = 2     // at-bat outcome / baserunning
            case critical = 3 // run scored

            static func < (lhs: Importance, rhs: Importance) -> Bool {
                lhs.rawValue < rhs.rawValue
            }

            static func from(naverType: Int?) -> Importance {
                switch naverType {
                case 24: return .critical
                case 13, 14, 23: return .high
                case 2: return .low     // substitution — TTS reads it, ticker skips
                case 7: return .medium
                case 0, 8: return .low  // inning header + batter intro — noise
                case 1: return .low
                // Unknown types default to medium so we still surface them
                // rather than silently dropping plays Naver added later.
                default: return .medium
                }
            }
        }
    }

    /// Live at-bat detail. Naver's currentGameState updates within a second
    /// or two of every pitch. All counts are 0-based (max 3 balls, 2 strikes,
    /// 2 outs in a normal flow; we allow one beyond just in case Naver
    /// briefly reports the transition state).
    struct LiveState: Equatable {
        let balls: Int
        let strikes: Int
        let outs: Int
        let onFirst: Bool
        let onSecond: Bool
        let onThird: Bool
        /// Resolved by pcode lookup against homeLineup/awayLineup.
        /// nil when the lineup roster wasn't included in the response (rare).
        let batterName: String?
        let batOrder: Int?
        let pitcherName: String?
        /// Which side is currently at bat. Derived from the most recent
        /// textRelay entry's homeOrAway flag (bottom of the inning = home
        /// batting). Lets the panel mark the batting team without a
        /// separate per-game attackingSide map.
        let attackingSide: Play.AttackingSide?
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
            let inn: Int?
            let homeOrAway: String?  // "0"=top/away, "1"=bottom/home
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
            let ball, strike, out: String?
            let base1, base2, base3: String?
            let pitcher, batter: String?
        }

        guard let outer = try? JSONDecoder().decode(Outer.self, from: raw),
              let trd = outer.result?.textRelayData
        else { return nil }

        // Header fields aren't in the relay payload — leave empty so the
        // view falls back to whatever the schedule API already showed
        // (game.statusInfo, etc.) without crashing.
        self.currentInning = trd.inn ?? 0
        self.currentHomeOrAway = trd.homeOrAway ?? "0"
        self.stadium = ""
        self.crowd = ""
        self.startTime = ""
        self.endTime = ""
        self.runTime = ""
        self.awayTeamName = ""
        self.homeTeamName = ""

        // Starting pitcher = first entry in each side's pitcher array. KBO's
        // relay lists the starter at index 0 and appends relievers as they
        // enter, so the array head stays stable for the whole game.
        let starters = Self.findStartingPitchers(rawData: raw)
        self.awayStartingPitcher = starters.away
        self.homeStartingPitcher = starters.home

        // All plays sorted by seqno ascending. The ViewModel paces them
        // out one-by-one via its queue runner; we keep `latestPlay` as a
        // convenience alias to the tail so the existing baseline-on-first-
        // observation logic still has something to show immediately.
        let plays = Self.collectPlays(in: raw)
        self.allPlays = plays
        self.latestPlay = plays.last

        // At-bat state — count + bases. Treat empty/missing fields as no
        // live state at all so pre-game / cancelled fetches don't render
        // a phantom "0-0, 0 out, bases empty" snapshot.
        if let cgs = trd.currentGameState,
           let ball = cgs.ball, let strike = cgs.strike, let out = cgs.out,
           !ball.isEmpty || !strike.isEmpty || !out.isEmpty {
            // Resolve pitcher/batter pcodes against both lineups. The pcode
            // is unique per player so scanning both rosters is safe and
            // avoids needing to know which side is currently fielding.
            let (batterName, batOrder) = Self.findBatter(rawData: raw, pcode: cgs.batter)
            let pitcherName = Self.findPitcher(rawData: raw, pcode: cgs.pitcher)
            self.liveState = LiveState(
                balls: Int(ball) ?? 0,
                strikes: Int(strike) ?? 0,
                outs: Int(out) ?? 0,
                onFirst: (cgs.base1 ?? "0") != "0",
                onSecond: (cgs.base2 ?? "0") != "0",
                onThird: (cgs.base3 ?? "0") != "0",
                batterName: batterName,
                batOrder: batOrder,
                pitcherName: pitcherName,
                attackingSide: plays.last?.attackingSide
            )
        } else {
            self.liveState = nil
        }

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

    /// Re-decode just enough of the relay payload to scan both lineups
    /// for matching pcodes. Done as a second pass so we don't have to
    /// thread lineup arrays through the main `init` shape.
    private struct LineupOuter: Decodable {
        struct Result: Decodable { let textRelayData: TextRelay? }
        struct TextRelay: Decodable {
            let homeLineup: Lineup?
            let awayLineup: Lineup?
        }
        struct Lineup: Decodable {
            let batter: [Player]?
            let pitcher: [Player]?
        }
        struct Player: Decodable {
            let pcode: String?
            let name: String?
            let batOrder: Int?
        }
        let result: Result?
    }

    private static func findBatter(rawData: Data, pcode: String?) -> (String?, Int?) {
        guard let pcode, !pcode.isEmpty,
              let outer = try? JSONDecoder().decode(LineupOuter.self, from: rawData),
              let trd = outer.result?.textRelayData
        else { return (nil, nil) }
        let pools = [trd.homeLineup?.batter, trd.awayLineup?.batter].compactMap { $0 }
        for pool in pools {
            if let p = pool.first(where: { $0.pcode == pcode }) {
                return (p.name, p.batOrder)
            }
        }
        return (nil, nil)
    }

    private static func findStartingPitchers(rawData: Data) -> (away: String?, home: String?) {
        guard let outer = try? JSONDecoder().decode(LineupOuter.self, from: rawData),
              let trd = outer.result?.textRelayData
        else { return (nil, nil) }
        let away = trd.awayLineup?.pitcher?.first?.name
        let home = trd.homeLineup?.pitcher?.first?.name
        return (away, home)
    }

    private static func findPitcher(rawData: Data, pcode: String?) -> String? {
        guard let pcode, !pcode.isEmpty,
              let outer = try? JSONDecoder().decode(LineupOuter.self, from: rawData),
              let trd = outer.result?.textRelayData
        else { return nil }
        let pools = [trd.homeLineup?.pitcher, trd.awayLineup?.pitcher].compactMap { $0 }
        for pool in pools {
            if let p = pool.first(where: { $0.pcode == pcode }) {
                return p.name
            }
        }
        return nil
    }

    /// Scan textRelays for every commentary line, sorted by seqno
    /// ascending. Naver puts every play (pitches, hits, subs, inning
    /// summary lines) into textRelays[].textOptions[]; the seqno is
    /// monotonically increasing across the whole game, so the caller can
    /// diff against a stored last-seen seqno to discover only the new
    /// plays since the previous poll. type 99 ("=====" inning dividers)
    /// is filtered out — it's display noise, not a play.
    static func collectPlays(in raw: Data) -> [Play] {
        struct Outer: Decodable {
            struct Result: Decodable { let textRelayData: Inner? }
            let result: Result?
        }
        struct Inner: Decodable { let textRelays: [Relay]? }
        struct Relay: Decodable {
            let inn: Int?
            // "1" = bottom of inning (home batting), "0" = top (away batting).
            let homeOrAway: String?
            let textOptions: [Option]?
        }
        struct Option: Decodable {
            let seqno: Int?
            let text: String?
            let type: Int?
        }

        guard let outer = try? JSONDecoder().decode(Outer.self, from: raw),
              let relays = outer.result?.textRelayData?.textRelays
        else { return [] }

        var collected: [Play] = []
        for relay in relays {
            guard let inning = relay.inn, let options = relay.textOptions else { continue }
            let side: Play.AttackingSide?
            switch relay.homeOrAway {
            case "1": side = .home
            case "0": side = .away
            default: side = nil
            }
            for opt in options {
                guard let seqno = opt.seqno,
                      let text = opt.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty,
                      opt.type != 99
                else { continue }
                var imp = Play.Importance.from(naverType: opt.type)
                // Promote fouls to medium so they show in the ticker —
                // at 2 strikes, BSO doesn't change and the user gets
                // zero feedback otherwise.
                if imp == .low, opt.type == 1, text.contains("파울") {
                    imp = .medium
                }
                collected.append(Play(
                    seqno: seqno,
                    inning: inning,
                    text: text,
                    attackingSide: side,
                    naverType: opt.type ?? 0,
                    importance: imp
                ))
            }
        }
        collected.sort { $0.seqno < $1.seqno }
        return collected
    }
}

