import Foundation
import SwiftUI

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

    // MARK: - Private

    private var pollTimer: Timer?
    private var fetchTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        selectedGameID = SettingsManager.shared.kboSelectedGameID
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

    // MARK: - Selection

    func select(_ game: KBOGame) {
        selectedGameID = (selectedGameID == game.gameId) ? nil : game.gameId
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
