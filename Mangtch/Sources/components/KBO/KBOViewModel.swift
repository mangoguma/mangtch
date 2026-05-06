import Foundation
import SwiftUI
import Combine
import AVFoundation

@Observable
@MainActor
final class KBOViewModel {
    // MARK: - Published state

    private(set) var games: [KBOGame] = []
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

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
            SettingsManager.shared.kboSelectedGameID = selectedGameID
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
    /// notifications on toggle. Synced back to SettingsManager via didSet
    /// for persistence. A computed property fronting SettingsManager
    /// directly didn't trigger SwiftUI re-renders because @Observable's
    /// tracking only sees changes on this object's own storage.
    var tickerEnabled: Bool = SettingsManager.shared.kboTickerEnabled {
        didSet {
            guard oldValue != tickerEnabled else { return }
            SettingsManager.shared.kboTickerEnabled = tickerEnabled
        }
    }
    var ttsEnabled: Bool = SettingsManager.shared.kboTextToSpeechEnabled {
        didSet {
            guard oldValue != ttsEnabled else { return }
            SettingsManager.shared.kboTextToSpeechEnabled = ttsEnabled
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

    private static let trackedPollSeconds: TimeInterval = 10
    private static let schedulePollLive: TimeInterval = 60
    private static let schedulePollIdle: TimeInterval = 300

    // MARK: - Init

    init() {
        selectedGameID = SettingsManager.shared.kboSelectedGameID

        // Snap back to today every time the panel is reopened. Without
        // this, a user who browsed back to yesterday and closed the
        // panel would still see yesterday next time. SwiftUI's .onAppear
        // doesn't help here because the expanded view stays in the
        // hierarchy at height=0 and never re-appears.
        EventBus.shared.stateChanges
            .filter { $0 == .expanded }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetToToday()
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
        fetchTask = Task { @MainActor in
            isLoading = true
            let fresh = await KBOService.fetchGames(date: date)
            // Guard against stale completions arriving after stopMonitoring
            // or after the user has navigated to a different day.
            guard !Task.isCancelled,
                  Calendar.korea.isDate(date, inSameDayAs: self.pendingDate)
            else { return }
            // Commit the date label and the games list together so the
            // header text and content swap in the same frame.
            self.displayedDate = date
            self.games = fresh
            self.lastError = nil
            self.isLoading = false
            // Auto-unpin a game once it transitions to finished or
            // cancelled. The wing already falls back to music via
            // hasContentToShow when isLive is false, but clearing the
            // pin too removes the accent fill on the row and matches
            // the user's mental model of "stop watching this game".
            if let pinnedID = self.selectedGameID,
               let pinned = fresh.first(where: { $0.gameId == pinnedID }),
               !pinned.isLive {
                self.selectedGameID = nil
                self.currentAttackingSide = nil
            }
            // Drop liveStates entries for games no longer present or
            // no longer live — leaving stale diamonds visible on a row
            // that's transitioned to "종료" would be misleading.
            let liveIds = Set(fresh.filter { $0.isLive }.map(\.gameId))
            self.liveStates = self.liveStates.filter { liveIds.contains($0.key) }
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
        // Always start a fresh day with the list collapsed — a row that
        // was open on the previous day's list points at a game that
        // isn't in the new fetch, and leaving it "open" keeps the panel
        // tall with no visible inline detail.
        collapse()
        pendingDate = new
    }

    func resetToToday() {
        collapse()
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
            collapse()
        } else {
            viewingGameID = game.gameId
            viewingLinescore = nil
            // Expanding a row also pins it to the wing — one tap covers
            // both "see the inning grid" and "watch this game from the
            // notch". hasContentToShow takes care of falling back to
            // music when the pinned game isn't live.
            selectedGameID = game.gameId
            fetchLinescoreNow(for: game)
            // Panel size syncs to actual rendered content via
            // contentHeightChanged(to:) — no static buffer needed here.
        }
    }

    func collapse() {
        viewingGameID = nil
        viewingLinescore = nil
        linescoreTask?.cancel()
        linescoreTask = nil
        selectedGameID = nil
        // KBOExpandedView's preference change will redrive the height
        // to match the now-shorter content; we don't reset eagerly here
        // to avoid a one-frame snap-then-grow during the collapse animation.
    }

    /// Natural content height when no row is expanded. Captured from the
    /// first preference report after games load, so the panel chrome's
    /// height (tab bar + outer paddings) stays implicit — we just track
    /// how much the content has *grown beyond* this baseline.
    private var compactContentHeight: CGFloat = 0

    /// Drive the panel height from the actual measured content size
    /// reported by KBOExpandedView's `.background` GeometryReader. We
    /// compare against the captured compact baseline instead of
    /// `maxExpandedHeight` directly — `maxExpandedHeight` includes the
    /// shared panel chrome (tab bar etc.), which is *not* in our content
    /// measurement, so subtracting it would chop ~24pt off every grow.
    func contentHeightChanged(to measured: CGFloat) {
        guard measured > 0 else { return }
        // Re-baseline whenever no row is open. Catches games-list changes
        // (date navigation, fetches) so the baseline tracks reality.
        if viewingGameID == nil {
            compactContentHeight = measured
        }
        let delta = max(0, measured - compactContentHeight)
        for vm in NotchWindowManager.shared.allViewModels {
            vm.additionalExpandedHeight = delta
        }
    }

    // MARK: - Wing pin

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
            // Linescore is stored only when the user is actually viewing
            // this game's detail. For pure background tracking (pinned
            // but not expanded) we just want the play side-effects.
            if self.viewingGameID == gameId {
                self.viewingLinescore = result
            }
            self.isLoadingLinescore = false
            // Always update the per-game live state map. Even non-tracked
            // games funnel into here when their fast timer fires, so each
            // row in the panel can render its own diamond/count.
            // Subscript-with-nil removes the key, which is what we want
            // when Naver clears the at-bat between innings.
            self.liveStates[gameId] = result?.liveState
            if let plays = result?.allPlays, !plays.isEmpty {
                self.handleNewPlays(plays, gameID: gameId)
            }
        }
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

        // Mirror the most recent play's attacking side immediately so the
        // score row's accent doesn't lag behind the queue.
        if let last = plays.last {
            currentAttackingSide = last.attackingSide
        }

        if isFirstObservation {
            // Baseline: jump to the most recent play so the wing isn't
            // blank on pin, but mark every prior seqno as already-seen.
            // No TTS — speaking a stale play that happened before the
            // user pinned would be jarring.
            if let last = plays.last {
                lastSeenSeqno = last.seqno
                if tickerEnabled {
                    latestPlayText = last.text
                    startQueueRunnerIfNeeded()  // schedules the eventual clear
                }
            }
            return
        }

        let fresh = plays.filter { $0.seqno > lastSeenSeqno }
        guard !fresh.isEmpty else { return }
        // Advance the seen-marker even for plays we drop below — otherwise
        // a flurry of low-importance pitches would re-evaluate every poll.
        lastSeenSeqno = fresh.last!.seqno
        // Per-pitch chatter (type 1) drowns out the actually-interesting
        // outcomes if it all hits the queue at 5s pacing. Filter to medium+
        // for the ticker so users see at-bat results, baserunning, and
        // scoring without 6-pitch counts in between.
        let displayable = fresh.filter { $0.importance >= .medium }
        guard !displayable.isEmpty else { return }
        playQueue.append(contentsOf: displayable)
        startQueueRunnerIfNeeded()
    }

    /// Run a single advance loop that pops one play every
    /// `playDisplayInterval` seconds. Idempotent — calling it while the
    /// loop is already running is a no-op, so each new poll can just
    /// append to `playQueue` and re-arm without worrying about overlap.
    private func startQueueRunnerIfNeeded() {
        guard queueRunnerTask == nil else { return }
        queueRunnerTask = Task { @MainActor in
            // Hold whatever's currently on the ticker for one interval
            // (the baseline-display case sets latestPlayText before
            // arming the runner with an empty queue) so the user has
            // time to read it before we either advance or clear.
            try? await Task.sleep(for: Self.playDisplayInterval)
            while !playQueue.isEmpty {
                if Task.isCancelled { break }
                let play = playQueue.removeFirst()
                if tickerEnabled {
                    latestPlayText = play.text
                }
                // TTS only narrates the events worth interrupting for —
                // at-bat outcomes, baserunning, scoring. Inning-start
                // headers and batter intros are useful in the ticker but
                // would feel chatty if read aloud every minute.
                if ttsEnabled && play.importance >= .high {
                    Self.speak(play.text)
                }
                try? await Task.sleep(for: Self.playDisplayInterval)
            }
            if !Task.isCancelled {
                latestPlayText = nil
            }
            queueRunnerTask = nil
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
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
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
