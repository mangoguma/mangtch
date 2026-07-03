import Foundation
import SwiftUI
import Combine
import AVFoundation
import Defaults

@Observable
@MainActor
final class KBOViewModel {
    // MARK: - Published state

    private(set) var games: [KBOGame] = []
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    /// Whether the notch panel is currently open. Gates the "hold wings on a
    /// non-today date" behavior so KBO only squats on the collapsed wings while
    /// the user is actively browsing — not with a date that drifted stale
    /// (e.g. across a KST midnight rollover) while the panel was closed.
    private(set) var isNotchOpen: Bool = false

    /// Date the UI is rendering. Lags `pendingDate` until a fetch lands —
    /// so the header label, "오늘" button visibility, and games list all
    /// flip in lockstep instead of the label snapping ahead of the
    /// network round-trip.
    private(set) var displayedDate: Date = KBOService.currentKBODate()

    /// Date the user has navigated to (drives fetches). Setting this
    /// kicks a fetch; `displayedDate` is committed atomically with the
    /// resulting games when the fetch completes.
    private var pendingDate: Date = KBOService.currentKBODate() {
        didSet {
            guard !Calendar.korea.isDate(oldValue, inSameDayAs: pendingDate) else { return }
            // Clear stale rows + error so the empty area immediately switches
            // to the loading state instead of showing the previous day's
            // games (or a stale "경기가 없어요") while the new fetch is in
            // flight. The header date label keeps lagging until commit, so
            // the panel reads as "loading <new date>" via the spinner row.
            self.games = []
            self.lastError = nil
            fetchNow()
        }
    }

    var isShowingToday: Bool {
        Calendar.korea.isDate(displayedDate, inSameDayAs: KBOService.currentKBODate())
    }

    /// Game ID the user pinned to the left wing. Nil = no pin.
    var selectedGameID: String? {
        didSet {
            guard oldValue != selectedGameID else { return }
            Defaults[.kboSelectedGameID] = selectedGameID
            // Tracked-game changed: drop any queued plays from the
            // previous game so the runner doesn't keep tickering them
            // after the user has moved on. The next poll for the new
            // game will re-baseline via lastSeenGameID.
            resetPlayQueue()
            // Re-target the 10s relay timer at the new tracked game
            // (or disarm if there is none).
            armTrackedPoll()
        }
    }

    var selectedGame: KBOGame? {
        guard let id = selectedGameID else { return nil }
        return games.first(where: { $0.gameId == id })
    }

    /// When set, the expanded panel switches from the day list to the
    /// inning-by-inning detail of this game. nil = list view.
    private(set) var viewingGameID: String?
    private(set) var viewingLinescore: KBOLinescore?
    private(set) var isLoadingLinescore: Bool = false

    var viewingGame: KBOGame? {
        guard let id = viewingGameID else { return nil }
        return games.first(where: { $0.gameId == id })
    }

    // MARK: - Live ticker state

    /// Most recent play text from the pinned (or viewed) live game.
    /// Auto-clears 5 s after being set so the right-wing ticker fades
    /// itself out instead of standing forever after one new play.
    private(set) var latestPlayText: String?
    /// Whichever side is currently at-bat for the tracked game. Persists
    /// (unlike latestPlayText) so the score row can highlight the
    /// attacking team continuously, not just for 5 s after a play.
    private(set) var currentAttackingSide: KBOLinescore.Play.AttackingSide?
    /// Latest at-bat state (count + bases) for **every** live game we've
    /// polled, keyed by gameId. The expanded panel reads this directly so
    /// each row's diamond/count cell stays populated, not just the
    /// pinned/viewed one. Tracked game refreshes at 10s; the rest at the
    /// schedule cadence (60s).
    private(set) var liveStates: [String: KBOLinescore.LiveState] = [:]
    /// Cached run scores from the linescore relay. Bridges the 5s tracked
    /// poll and the 60s schedule poll so compact/expanded scores stay
    /// current without waiting for the full schedule response.
    private(set) var liveScores: [String: (away: Int, home: Int)] = [:]

    /// Cached starting pitchers per gameId. Populated by background relay
    /// fetches kicked from each schedule poll so the collapsed game row
    /// can show selectable lineup info without expanding. Survives day
    /// changes (different gameIds) — once a starter is cached for a game
    /// we never re-fetch it.
    private(set) var startingPitchers: [String: KBOStarters] = [:]
    private var pitcherPrefetchInFlight: Set<String> = []

    /// Convenience accessor for the right-wing view, which only cares
    /// about the tracked game. Computed off `liveStates` so callers stay
    /// in sync automatically.
    var currentLiveState: KBOLinescore.LiveState? {
        guard let id = trackedGame?.gameId else { return nil }
        return liveStates[id]
    }
    /// Highest play seqno we've already enqueued for display. Anything
    /// with a higher seqno on the next poll is "new" and gets appended to
    /// `playQueue`. Reset to 0 whenever the tracked game changes so the
    /// next observation re-baselines.
    private var lastSeenSeqno: Int = 0
    /// Which inning half we last processed. Used to detect inning
    /// transitions and trigger a backfill fetch for missed end-of-half plays.
    private var lastSeenInning: Int = 0
    private var lastSeenHomeOrAway: String = ""
    /// Guards the 2s immediate-refetch cooldown after new plays arrive.
    private var lastPlayRefetchTime: Date = .distantPast
    /// FIFO of plays waiting to be tickered out, oldest first. The queue
    /// runner pops one every `playDisplayInterval` seconds so the user
    /// sees each commentary line in order instead of jumping straight to
    /// the most recent one.
    private var playQueue: [KBOLinescore.Play] = []
    private var queueRunnerTask: Task<Void, Never>?
    /// How long each play stays on the ticker before the runner advances.
    /// Tuned to match the previous single-line clear delay.
    private static let playDisplayInterval: Duration = .seconds(5)

    /// Stored on KBOViewModel so the @Observable macro can fire change
    /// notifications on toggle. Synced back to Defaults via didSet
    /// for persistence. A computed property fronting Defaults
    /// directly didn't trigger SwiftUI re-renders because @Observable's
    /// tracking only sees changes on this object's own storage.
    var tickerEnabled: Bool = Defaults[.kboTickerEnabled] {
        didSet {
            guard oldValue != tickerEnabled else { return }
            Defaults[.kboTickerEnabled] = tickerEnabled
        }
    }
    var ttsEnabled: Bool = Defaults[.kboTextToSpeechEnabled] {
        didSet {
            guard oldValue != ttsEnabled else { return }
            Defaults[.kboTextToSpeechEnabled] = ttsEnabled
        }
    }
    var soundEffectsEnabled: Bool = Defaults[.kboSoundEffectsEnabled] {
        didSet {
            guard oldValue != soundEffectsEnabled else { return }
            Defaults[.kboSoundEffectsEnabled] = soundEffectsEnabled
        }
    }

    /// Game whose plays should be tickered/spoken. Priority: viewed >
    /// pinned. Both share the same relay-fetch path.
    private var trackedGame: KBOGame? {
        viewingGame ?? selectedGame
    }

    // MARK: - Private

    /// Drives the all-games schedule fetch (60s while any game is live,
    /// 5min otherwise). Slow on purpose — schedule rows barely change
    /// outside of score updates, which the per-game relay covers faster.
    private var pollTimer: Timer?
    /// Fast cadence (10s) for the tracked game's relay. Armed only while
    /// `trackedGame` exists and is live; cleared the moment it ends or
    /// the user unpins, to avoid hammering Naver for a finished game.
    private var trackedTimer: Timer?
    /// gameId currently driving `trackedTimer`. Lets `armTrackedPoll` be
    /// idempotent across schedule polls — re-arming for the same game is
    /// a no-op so we don't reset the 10s window every 60s.
    private var trackedTimerGameId: String?
    private var fetchTask: Task<Void, Never>?
    private var linescoreTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private static let trackedPollSeconds: TimeInterval = 5
    private static let schedulePollLive: TimeInterval = 60
    private static let schedulePollIdle: TimeInterval = 300

    // MARK: - Init

    init() {
        selectedGameID = Defaults[.kboSelectedGameID]

        // Snap back to today every time the panel is reopened. Without
        // this, a user who browsed back to yesterday and closed the
        // panel would still see yesterday next time. SwiftUI's .onAppear
        // doesn't help here because the expanded view stays in the
        // hierarchy at height=0 and never re-appears.
        // Use rewindDateOnly: keep the expanded row + pinned game intact
        // so the user's live broadcast selection survives close/reopen.
        // Mangtch's EventBus replaced with NotificationCenter — the notch
        // state-change notification is posted by BoringViewModel.open().
        NotificationCenter.default
            .publisher(for: .boringNotchDidOpen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isNotchOpen = true
                self?.rewindDateOnly()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .boringNotchDidClose)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isNotchOpen = false
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Called by KBOWidget.activate(). Starts the periodic fetch and runs
    /// one immediately so the expanded view never opens to a blank list.
    func startMonitoring() {
        fetchNow()
        scheduleNextPoll()
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        trackedTimer?.invalidate()
        trackedTimer = nil
        trackedTimerGameId = nil
        fetchTask?.cancel()
        fetchTask = nil
        linescoreTask?.cancel()
        linescoreTask = nil
        resetPlayQueue()
        // If the widget was holding the panel open, hand the height back.
        if viewingGameID != nil {
            collapse()
        }
    }

    // MARK: - Fetch

    private func fetchNow() {
        fetchTask?.cancel()
        let date = pendingDate
        // Flip the spinner on synchronously so any render that happens
        // between fetchNow() and the Task body picking up the actor (e.g.
        // user opens the panel right after KBOWidget.activate) shows the
        // loading state instead of a momentarily stale "경기가 없어요".
        isLoading = true
        fetchTask = Task { @MainActor in
            let fetched = await KBOService.fetchGames(date: date)
            // Guard against stale completions arriving after stopMonitoring
            // or after the user has navigated to a different day.
            guard !Task.isCancelled,
                  Calendar.korea.isDate(date, inSameDayAs: self.pendingDate)
            else { return }
            // Commit the date label and the games list together so the
            // header text and content swap in the same frame.
            self.displayedDate = date
            if let fresh = fetched {
                self.games = fresh
                self.lastError = nil
            } else {
                // Network/decode failure — clear stale games for the new
                // date so the row list doesn't lie, and surface lastError
                // so the empty state renders an error message instead of
                // "no games scheduled".
                self.games = []
                self.lastError = "일정을 불러오지 못했어요"
            }
            let fresh = self.games
            self.isLoading = false
            // Auto-unpin a game once it transitions to finished or
            // cancelled. Scheduled games are intentionally left pinned —
            // toggleExpand pins on tap, and `!isLive` previously matched
            // both finished AND scheduled, so opening a pre-game row got
            // its pin (and accent fill) wiped on the next poll.
            if let pinnedID = self.selectedGameID,
               let pinned = fresh.first(where: { $0.gameId == pinnedID }),
               pinned.isFinished || pinned.cancel {
                self.selectedGameID = nil
                self.currentAttackingSide = nil
            }
            // Drop liveStates entries for games no longer present or
            // no longer live — leaving stale diamonds visible on a row
            // that's transitioned to "종료" would be misleading.
            let liveIds = Set(fresh.filter { $0.isLive }.map(\.gameId))
            self.liveStates = self.liveStates.filter { liveIds.contains($0.key) }
            // Kick a one-shot starter prefetch for any game we don't have
            // cached pitchers for yet. Starters never change once
            // announced, so this fires at most once per gameId per app
            // lifetime. Skipped for games that already cached, or for
            // ones that will be picked up by the live-state fetch path
            // below (cache is also written from those response handlers).
            for game in fresh where self.startingPitchers[game.gameId] == nil {
                self.prefetchStarters(for: game)
            }
            // Kick a lightweight relay refresh for every live game *except*
            // the tracked one. The tracked game has its own 10s timer that
            // also drives play-queue/TTS; non-tracked games only need the
            // bases/count snapshot so the panel's per-row cells render.
            let trackedId = self.trackedGame?.gameId
            for game in fresh where game.isLive && game.gameId != trackedId {
                self.fetchLiveStateNow(for: game)
            }
            // Tracked game's relay runs on its own 10s timer — just
            // ensure it's armed (or disarmed if the game just ended).
            // armTrackedPoll fires an immediate fetch when first arming,
            // so newly-live tracked games still refresh promptly.
            self.armTrackedPoll()
            // Re-arm the schedule timer with whatever cadence now matches
            // reality (60s during live windows, 5min otherwise).
            self.scheduleNextPoll()
        }
    }

    // MARK: - Day Navigation

    /// Shifts the browsed day by ±1. The visible date won't change until
    /// the resulting fetch lands — see `pendingDate`.
    func shiftDay(by days: Int) {
        guard let new = Calendar.korea.date(byAdding: .day, value: days, to: pendingDate) else { return }
        // Collapse only the inline expanded row (which points at a game
        // from the previous day's list and would leave the panel tall
        // with no visible detail). The wing pin (`selectedGameID`) is
        // preserved so a live broadcast the user is following stays put
        // while they browse other days.
        collapseInline()
        pendingDate = new
    }

    func resetToToday() {
        collapse()
        pendingDate = KBOService.currentKBODate()
    }

    /// Re-anchor the date to today without disturbing the user's expanded
    /// row, pinned game, or loaded linescore. Used on panel reopen so a
    /// live broadcast the user was watching stays open across close/open.
    /// If the date actually changes, `pendingDate.didSet` triggers a
    /// fetch; a stale `viewingGameID` whose game isn't in the new day's
    /// list will simply render nothing until the user picks another row.
    func rewindDateOnly() {
        pendingDate = KBOService.currentKBODate()
    }

    /// Schedule (all-games) cadence: 60s during live windows so the row
    /// list reflects score changes; 5min otherwise. The tracked game's
    /// own relay polls separately at `trackedPollSeconds`, so dropping
    /// the schedule cadence to 60s doesn't slow down the score on the
    /// game the user is actually watching.
    private var pollInterval: TimeInterval {
        let anyLive = games.contains(where: { $0.isLive })
        return anyLive ? Self.schedulePollLive : Self.schedulePollIdle
    }

    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fetchNow()
            }
        }
    }

    /// Arm (or disarm) the fast 10s relay timer for the tracked game.
    /// Idempotent — call freely from anywhere tracked-game state may
    /// have changed (pin/unpin, expand/collapse, schedule fetch).
    /// Fires an immediate relay so the user doesn't wait up to 10s for
    /// the first refresh after switching games.
    private func armTrackedPoll() {
        guard let tracked = trackedGame, tracked.isLive else {
            trackedTimer?.invalidate()
            trackedTimer = nil
            trackedTimerGameId = nil
            return
        }
        // Already armed for this exact game — leave the running 10s
        // timer alone so periodic schedule fetches don't reset it.
        if trackedTimerGameId == tracked.gameId, trackedTimer != nil {
            return
        }
        trackedTimer?.invalidate()
        trackedTimer = nil
        trackedTimerGameId = tracked.gameId
        // Immediate kick so a freshly-pinned live game shows live state
        // / plays without a 10s gap.
        fetchLinescoreNow(for: tracked)
        trackedTimer = Timer.scheduledTimer(
            withTimeInterval: Self.trackedPollSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Re-check liveness on every tick — game can end mid-session.
                guard let tracked = self.trackedGame, tracked.isLive else {
                    self.trackedTimer?.invalidate()
                    self.trackedTimer = nil
                    self.trackedTimerGameId = nil
                    return
                }
                self.fetchLinescoreNow(for: tracked)
            }
        }
    }

    // MARK: - Inline expansion

    /// Tap a row → reveal that game's box score inline beneath it. Tapping
    /// the same row again, or another row, collapses the previous one.
    /// Triggers a one-shot linescore fetch; live games will refresh again
    /// on the next poll.
    func toggleExpand(_ game: KBOGame) {
        if viewingGameID == game.gameId {
            // Re-tap: collapse inline and unpin. Distinct from panel close
            // (which calls collapse() without clearing the pin so the live
            // broadcast survives close/reopen).
            collapseInline()
            selectedGameID = nil
            currentAttackingSide = nil
        } else {
            viewingGameID = game.gameId
            viewingLinescore = nil
            // Expanding a row also pins it to the wing — one tap covers
            // both "see the inning grid" and "watch this game from the
            // notch". hasContentToShow takes care of falling back to
            // music when the pinned game isn't live.
            selectedGameID = game.gameId
            fetchLinescoreNow(for: game)
        }
    }

    func collapse() {
        collapseInline()
        // Pin persists — the user's live broadcast selection survives
        // panel close/reopen. selectedGameID is only cleared by toggleExpand
        // re-tap (explicit user unpin) or when the game ends/is cancelled.
    }

    /// Collapse just the inline row expansion, leaving the wing pin
    /// (`selectedGameID`) intact. Used by date navigation so a user
    /// browsing other days doesn't lose the live broadcast they had
    /// pinned to the wing.
    func collapseInline() {
        viewingGameID = nil
        viewingLinescore = nil
        linescoreTask?.cancel()
        linescoreTask = nil
    }

    /// Toggle whether the currently-viewed (or passed) game is pinned to
    /// the left wing. Pin only sticks if the game is live; pinning a
    /// non-live game is allowed but the wing falls back to music via
    /// hasContentToShow until the game starts.
    func togglePin(for game: KBOGame) {
        selectedGameID = (selectedGameID == game.gameId) ? nil : game.gameId
    }

    // MARK: - Linescore

    private func fetchLinescoreNow(for game: KBOGame) {
        linescoreTask?.cancel()
        let gameId = game.gameId
        let season = Self.season(from: game)
        linescoreTask = Task { @MainActor in
            self.isLoadingLinescore = true
            let result = await KBOService.fetchLinescore(gameId: gameId, season: season)
            guard !Task.isCancelled else { return }

            if self.viewingGameID == gameId {
                self.viewingLinescore = result
            }
            self.isLoadingLinescore = false

            // Update live score cache from R totals so compact/expanded
            // views reflect the score within 5s instead of waiting 60s.
            if let away = result?.awayTotals?.runs, let home = result?.homeTotals?.runs {
                self.liveScores[gameId] = (away: away, home: home)
            }

            // Always seed liveState from the full relay response — it carries
            // resolved pitcher/batter names that play-level snapshots omit.
            // The tracked game's BSO will be updated again by handleNewPlays
            // (per-play snapshots), while the name-preservation fix in both
            // handleNewPlays and the queue runner keeps names intact.
            self.liveStates[gameId] = result?.liveState

            self.cacheStarters(from: result, gameId: gameId)

            // Inning transition detection: if the linescore reports a new
            // half-inning, the previous half may have ended between polls.
            // Backfill its specific relay to recover any missed tail plays.
            var backfillPlays: [KBOLinescore.Play] = []
            if let r = result, r.currentInning > 0 {
                let newInning = r.currentInning
                let newHalf = r.currentHomeOrAway
                if self.lastSeenInning > 0
                   && (newInning != self.lastSeenInning || newHalf != self.lastSeenHomeOrAway) {
                    let prevInning = self.lastSeenInning
                    let prevHalf = self.lastSeenHomeOrAway
                    backfillPlays = await KBOService.fetchRelay(
                        gameId: gameId, inning: prevInning, homeOrAway: prevHalf
                    )
                }
                self.lastSeenInning = newInning
                self.lastSeenHomeOrAway = newHalf
            }

            guard !Task.isCancelled else { return }

            // Merge backfill before current plays so the queue sees events
            // in chronological order: end-of-previous-half → new-half.
            // Deduplicate by seqno: the same boundary play can appear in
            // both the backfill relay and the linescore allPlays response.
            let currentPlays = result?.allPlays ?? []
            let allPlays: [KBOLinescore.Play]
            if backfillPlays.isEmpty {
                allPlays = currentPlays
            } else {
                var seen = Set<Int>()
                allPlays = (backfillPlays + currentPlays)
                    .filter { seen.insert($0.seqno).inserted }
                    .sorted { $0.seqno < $1.seqno }
            }

            if !allPlays.isEmpty {
                self.handleNewPlays(allPlays, gameID: gameId)
            }
        }
    }

    /// Background fetch whose only job is to populate `startingPitchers`
    /// for games whose lineups we haven't seen yet (cancelled, scheduled,
    /// or finished games that never went through fetchLinescoreNow /
    /// fetchLiveStateNow). Single-flight per gameId.
    private func prefetchStarters(for game: KBOGame) {
        let gameId = game.gameId
        guard !pitcherPrefetchInFlight.contains(gameId) else { return }
        pitcherPrefetchInFlight.insert(gameId)
        let season = Self.season(from: game)
        Task { @MainActor in
            defer { self.pitcherPrefetchInFlight.remove(gameId) }
            let result = await KBOService.fetchLinescore(gameId: gameId, season: season)
            self.cacheStarters(from: result, gameId: gameId)
        }
    }

    /// Merge starters from a relay response into the cache. Only writes
    /// when at least one side is present so a transient empty payload
    /// (lineup not yet published) doesn't poison a previously-good entry.
    private func cacheStarters(from line: KBOLinescore?, gameId: String) {
        guard let line, line.awayStartingPitcher != nil || line.homeStartingPitcher != nil
        else { return }
        let next = KBOStarters(away: line.awayStartingPitcher,
                               home: line.homeStartingPitcher)
        guard self.startingPitchers[gameId] != next else { return }
        self.startingPitchers[gameId] = next
    }

    /// Slim relay fetch for a non-tracked live game — only updates
    /// `liveStates[gameId]`, never touches viewingLinescore or the play
    /// queue. Routing non-tracked games through `fetchLinescoreNow` would
    /// corrupt `lastSeenGameID` (it'd flip to whatever game finished
    /// fetching most recently) and leak phantom plays into the tracked
    /// game's ticker.
    private func fetchLiveStateNow(for game: KBOGame) {
        let gameId = game.gameId
        let season = Self.season(from: game)
        Task { @MainActor in
            let result = await KBOService.fetchLinescore(gameId: gameId, season: season)
            // Game may have ended or fallen off the slate between the
            // fetch firing and resolving — drop in that case rather than
            // leaving a stale diamond.
            guard self.games.contains(where: { $0.gameId == gameId && $0.isLive }) else {
                self.liveStates.removeValue(forKey: gameId)
                return
            }
            self.liveStates[gameId] = result?.liveState
            if let away = result?.awayTotals?.runs, let home = result?.homeTotals?.runs {
                self.liveScores[gameId] = (away: away, home: home)
            }
            self.cacheStarters(from: result, gameId: gameId)
        }
    }

    // MARK: - Play detection / ticker / TTS

    private var lastSeenGameID: String?

    /// Diff the play stream from this fetch against `lastSeenSeqno` and
    /// enqueue only the genuinely new plays for the ticker / TTS pipeline.
    /// First observation per game shows just the most recent line as a
    /// baseline (we don't want to ticker through hours of past plays when
    /// the user pins or switches games mid-broadcast); subsequent polls
    /// append every play that's appeared since the last poll, so the user
    /// sees them in order even if multiple landed between polls.
    private func handleNewPlays(_ plays: [KBOLinescore.Play], gameID: String) {
        let isFirstObservation = (lastSeenGameID != gameID)
        if isFirstObservation {
            lastSeenGameID = gameID
            lastSeenSeqno = 0
            playQueue.removeAll()
        }

        if let last = plays.last {
            currentAttackingSide = last.attackingSide
            // Apply the latest play's BSO snapshot immediately so the
            // tracked game's diamond/count is never more than one poll stale.
            // Preserve pitcher/batter names — play snapshots carry nil names
            // (no per-play pcode lookup) so they must come from the previous
            // liveState, which fetchLinescoreNow seeds with resolved names.
            if let snap = last.liveSnapshot {
                let prev = liveStates[gameID]
                liveStates[gameID] = KBOLinescore.LiveState(
                    balls: snap.balls,
                    strikes: snap.strikes,
                    outs: snap.outs,
                    onFirst: snap.onFirst,
                    onSecond: snap.onSecond,
                    onThird: snap.onThird,
                    batterName: snap.batterName ?? prev?.batterName,
                    batOrder: snap.batOrder ?? prev?.batOrder,
                    pitcherName: snap.pitcherName ?? prev?.pitcherName,
                    attackingSide: snap.attackingSide ?? prev?.attackingSide
                )
            }
        }

        if isFirstObservation {
            if let last = plays.last {
                lastSeenSeqno = last.seqno
                if tickerEnabled {
                    latestPlayText = last.text
                    startQueueRunnerIfNeeded()
                }
            }
            return
        }

        let fresh = plays.filter { $0.seqno > lastSeenSeqno }
        guard !fresh.isEmpty else { return }
        lastSeenSeqno = fresh.last!.seqno

        // Medium+ plays hit the visual ticker. Type 2 (substitution) and
        // type 8 (batter intro) are low-importance but still enter the queue
        // so TTS can announce lineup changes without polluting the ticker.
        let displayable = fresh.filter {
            $0.importance >= .medium || $0.naverType == 2 || $0.naverType == 8
        }
        if !displayable.isEmpty {
            // Guard against the same seqno reaching the queue twice (e.g.
            // via a concurrent backfill + immediate-refetch race).
            let queuedSeqnos = Set(playQueue.map(\.seqno))
            let toAdd = displayable.filter { !queuedSeqnos.contains($0.seqno) }
            if !toAdd.isEmpty {
                playQueue.append(contentsOf: toAdd)
                startQueueRunnerIfNeeded()
            }
        }

        // Immediately re-fetch after new plays land so rapidly-arriving
        // plays (e.g. score, next batter intro) appear quickly. A 2s
        // cooldown prevents overlapping fetches on a flurry of updates.
        scheduleImmediateRefetch(for: gameID)
    }

    private func scheduleImmediateRefetch(for gameID: String) {
        let cooldown: TimeInterval = 2
        guard Date().timeIntervalSince(lastPlayRefetchTime) > cooldown else { return }
        guard let game = games.first(where: { $0.gameId == gameID }), game.isLive else { return }
        lastPlayRefetchTime = Date()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(cooldown))
            guard let game = self.games.first(where: { $0.gameId == gameID }), game.isLive,
                  self.trackedGame?.gameId == gameID else { return }
            self.fetchLinescoreNow(for: game)
        }
    }

    /// Run a single advance loop that pops one play every
    /// `playDisplayInterval` seconds. Idempotent — calling it while the
    /// loop is already running is a no-op, so each new poll can just
    /// append to `playQueue` and re-arm without worrying about overlap.
    private func startQueueRunnerIfNeeded() {
        guard queueRunnerTask == nil else { return }
        queueRunnerTask = Task { @MainActor in
            try? await Task.sleep(for: Self.playDisplayInterval)
            while !playQueue.isEmpty {
                if Task.isCancelled { break }
                let play = playQueue.removeFirst()

                // Sync BSO to the snapshot captured at play time so the
                // diamond/count advances in lockstep with the ticker text.
                // Preserve pitcher/batter names from the previous state —
                // collectPlays snapshots carry nil names (no pcode lookup
                // per-play) and would otherwise wipe the names that
                // fetchLinescoreNow resolved on the most recent full fetch.
                if let snap = play.liveSnapshot, let gid = self.trackedGame?.gameId {
                    let prev = self.liveStates[gid]
                    self.liveStates[gid] = KBOLinescore.LiveState(
                        balls: snap.balls,
                        strikes: snap.strikes,
                        outs: snap.outs,
                        onFirst: snap.onFirst,
                        onSecond: snap.onSecond,
                        onThird: snap.onThird,
                        batterName: snap.batterName ?? prev?.batterName,
                        batOrder: snap.batOrder ?? prev?.batOrder,
                        pitcherName: snap.pitcherName ?? prev?.pitcherName,
                        attackingSide: snap.attackingSide ?? prev?.attackingSide
                    )
                }

                let isTTSOnly = play.naverType == 2 || play.naverType == 8
                if self.tickerEnabled {
                    self.latestPlayText = play.text
                }

                if self.soundEffectsEnabled {
                    if let sound = KBOSoundManager.shared.soundForPlay(
                        play.text, type: play.naverType, importance: play.importance
                    ) {
                        KBOSoundManager.shared.play(sound)
                    }
                }

                if self.ttsEnabled && (play.importance >= .high || isTTSOnly) {
                    Self.speak(play.text)
                }

                try? await Task.sleep(for: Self.playDisplayInterval)
            }
            if !Task.isCancelled {
                self.latestPlayText = nil
            }
            self.queueRunnerTask = nil
        }
    }

    /// Drop any queued plays and stop the runner. Used when the tracked
    /// game changes (pin/unpin, collapse) so we don't keep tickering
    /// stale plays from a game the user is no longer watching.
    private func resetPlayQueue() {
        queueRunnerTask?.cancel()
        queueRunnerTask = nil
        playQueue.removeAll()
        latestPlayText = nil
        lastSeenInning = 0
        lastSeenHomeOrAway = ""
    }

    /// In-process synthesizer so utterance start latency matches the
    /// ticker's text update — spawning `/usr/bin/say` per play used to add
    /// hundreds of ms of process boot before the first phoneme, which made
    /// audio visibly trail the ticker. AVSpeechSynthesizer also queues
    /// successive utterances internally so back-to-back plays don't
    /// overlap.
    nonisolated(unsafe) private static let synthesizer = AVSpeechSynthesizer()

    /// Read the play aloud. Korean voice since plays are written in Korean.
    private static func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        // Prefer Yuna Premium for natural-sounding Korean. Falls back to
        // any installed ko-KR voice if Yuna Premium isn't downloaded.
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.ko-KR.Yuna")
                       ?? AVSpeechSynthesisVoice(language: "ko-KR")
        synthesizer.speak(utterance)
    }

    /// Pull the season year out of the game's date — KBO's endpoint needs
    /// it as a separate parameter.
    private static func season(from game: KBOGame) -> Int {
        let calendar = Calendar.korea
        let parts = game.gameDateTime.split(separator: "-")
        if let first = parts.first, let year = Int(first) { return year }
        return calendar.component(.year, from: Date())
    }
}

extension Calendar {
    /// KBO is played in Korea — bucket all "same day" comparisons against
    /// Asia/Seoul so a user in San Francisco doesn't see yesterday's games
    /// after midnight local but before midnight KST.
    static let korea: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return cal
    }()
}

extension Notification.Name {
    /// Posted by BoringViewModel.open() so widgets can react to panel opening.
    /// Replaces Mangtch's EventBus.stateChanges(.expanded) publisher.
    static let boringNotchDidOpen = Notification.Name("boringNotchDidOpen")
    /// Posted by BoringViewModel.close() — the collapse counterpart so widgets
    /// can tell they're no longer being actively browsed.
    static let boringNotchDidClose = Notification.Name("boringNotchDidClose")
}
