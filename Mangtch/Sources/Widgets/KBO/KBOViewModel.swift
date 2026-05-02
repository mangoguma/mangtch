import Foundation
import SwiftUI
import Combine

@Observable
@MainActor
final class KBOViewModel {
    // MARK: - Published state

    private(set) var games: [KBOGame] = []
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    /// Date currently being browsed in the expanded view. Defaults to
    /// today (KBO timezone). Doesn't persist across launches — opening the
    /// widget should always start on today.
    var displayedDate: Date = KBOService.currentKBODate() {
        didSet {
            guard !Calendar.korea.isDate(oldValue, inSameDayAs: displayedDate) else { return }
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
    private var lastSeenSeqno: Int = 0
    private var tickerClearTask: Task<Void, Never>?

    /// Mirror SettingsManager.kboTickerEnabled / kboTextToSpeechEnabled
    /// here so SwiftUI views observing this @Observable can react instantly
    /// to toggle-button taps from the wing without going through defaults.
    var tickerEnabled: Bool {
        get { SettingsManager.shared.kboTickerEnabled }
        set { SettingsManager.shared.kboTickerEnabled = newValue }
    }
    var ttsEnabled: Bool {
        get { SettingsManager.shared.kboTextToSpeechEnabled }
        set { SettingsManager.shared.kboTextToSpeechEnabled = newValue }
    }

    /// Game whose plays should be tickered/spoken. Priority: viewed >
    /// pinned. Both share the same relay-fetch path.
    private var trackedGame: KBOGame? {
        viewingGame ?? selectedGame
    }

    // MARK: - Private

    private var pollTimer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var linescoreTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

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
        fetchTask?.cancel()
        fetchTask = nil
        linescoreTask?.cancel()
        linescoreTask = nil
        // If the widget was holding the panel open, hand the height back.
        if viewingGameID != nil {
            collapse()
        }
    }

    // MARK: - Fetch

    private func fetchNow() {
        fetchTask?.cancel()
        let date = displayedDate
        fetchTask = Task { @MainActor in
            isLoading = true
            let fresh = await KBOService.fetchGames(date: date)
            // Guard against stale completions arriving after stopMonitoring
            // or after the user has navigated to a different day.
            guard !Task.isCancelled,
                  Calendar.korea.isDate(date, inSameDayAs: self.displayedDate)
            else { return }
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
            }
            // Refresh the relay (linescore + textRelays) for whichever
            // game we're tracking — the one being viewed in detail, or
            // failing that, the pinned wing game. This is what feeds new
            // plays into the right-wing ticker and TTS even when the
            // panel isn't expanded.
            if let tracked = self.trackedGame, tracked.isLive {
                self.fetchLinescoreNow(for: tracked)
            }
            // Re-arm the timer with whatever cadence now matches reality
            // (live game polling is faster than scheduled-only polling).
            self.scheduleNextPoll()
        }
    }

    // MARK: - Day Navigation

    /// Shifts the displayed day by ±1. Triggers a fresh fetch via didSet.
    func shiftDay(by days: Int) {
        guard let new = Calendar.korea.date(byAdding: .day, value: days, to: displayedDate) else { return }
        displayedDate = new
    }

    func resetToToday() {
        displayedDate = KBOService.currentKBODate()
    }

    /// 30s while any game is live, 5min otherwise. Matches what most
    /// scoreboard apps do — live games change scores fast, scheduled and
    /// final games barely change at all.
    private var pollInterval: TimeInterval {
        let anyLive = games.contains(where: { $0.isLive })
        return anyLive ? 30 : 300
    }

    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fetchNow()
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

    /// Compute the panel height KBO needs based on the number of games
    /// and whether one of them is expanded inline, then ask NotchViewModel
    /// to grow (or shrink) to match. Driven from .onAppear / .onChange
    /// in KBOExpandedView, since SwiftUI's GeometryReader inside a
    /// .frame-constrained ancestor reports the constrained size, not the
    /// natural one — making intrinsic measurement unworkable here.
    func recomputePanelHeight() {
        // Empirical row metrics. Compact row = 22pt logo + 14pt padding.
        // Expanded extra = 3 grid rows (20pt) + divider + 14pt padding.
        let perRow: CGFloat = 36
        let rowSpacing: CGFloat = 4
        let headerSection: CGFloat = 36   // KBO label row (30) + spacing below (6)
        let outerPadding: CGFloat = 16    // top + bottom of root VStack
        let expandedExtra: CGFloat = 80   // inline grid + divider + padding
        let safetyBuffer: CGFloat = 12    // SwiftUI font rendering / spacing slack

        let count = max(games.count, 1)
        let rowsTotal = CGFloat(count) * perRow + CGFloat(count - 1) * rowSpacing
        let extra = (viewingGameID != nil) ? expandedExtra : 0

        let needed = headerSection + rowsTotal + extra + outerPadding + safetyBuffer
        let additional = needed - NotchViewModel.shared.maxExpandedHeight
        // Only ever grow the panel — keep maxExpandedHeight as the floor
        // so other widgets aren't squeezed if KBO would otherwise shrink it.
        NotchViewModel.shared.additionalExpandedHeight = max(0, additional)
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
            if let play = result?.latestPlay {
                self.handleNewPlay(play, gameID: gameId)
            }
        }
    }

    // MARK: - Play detection / ticker / TTS

    private var lastSeenGameID: String?

    /// Decide whether the latest play seen in this fetch is genuinely new
    /// for the tracked game, and surface it to the ticker / TTS pipeline.
    /// First observation per game is treated as baseline so we don't blast
    /// every play in the recent history at once when the user pins or
    /// switches games mid-broadcast.
    private func handleNewPlay(_ play: KBOLinescore.Play, gameID: String) {
        let isFirstObservation = (lastSeenGameID != gameID)
        if isFirstObservation {
            lastSeenGameID = gameID
            lastSeenSeqno = 0
        }
        guard play.seqno > lastSeenSeqno else { return }
        lastSeenSeqno = play.seqno

        // Show the latest play immediately, even on the first poll for a
        // newly-pinned game — otherwise the wing sits at "중계 대기 중"
        // until the next pitch, which feels broken.
        if tickerEnabled {
            latestPlayText = play.text
            scheduleTickerClear()
        }
        // Skip TTS on the first observation so we don't speak a stale
        // play from before the user pinned the game.
        if ttsEnabled && !isFirstObservation {
            Self.speak(play.text)
        }
    }

    private func scheduleTickerClear() {
        tickerClearTask?.cancel()
        let snapshot = latestPlayText
        tickerClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            // Only clear if it's still the same play — a new one would
            // have already replaced and rescheduled.
            if latestPlayText == snapshot {
                latestPlayText = nil
            }
        }
    }

    /// Read the play aloud via macOS `say`. Detached so URLSession poll
    /// timing isn't affected by the audio runtime. Korean voice ("Yuna")
    /// since plays are written in Korean.
    private static func speak(_ text: String) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", "Yuna", text]
            try? process.run()
        }
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
