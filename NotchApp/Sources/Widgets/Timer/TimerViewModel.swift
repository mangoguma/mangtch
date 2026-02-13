import SwiftUI
import Combine

enum TimerMode: String, CaseIterable {
    case countdown = "Timer"
    case stopwatch = "Stopwatch"
}

enum TimerState: Equatable {
    case idle
    case running
    case paused
    case finished
}

@Observable
@MainActor
final class TimerViewModel {
    // MARK: - State

    private(set) var state: TimerState = .idle
    private(set) var mode: TimerMode = .countdown

    /// Elapsed time in seconds (stopwatch) or remaining time (countdown)
    private(set) var displayTime: TimeInterval = 0

    /// Total countdown duration set by user (seconds)
    var countdownDuration: TimeInterval = 300 // 5 minutes default

    /// Progress 0.0 → 1.0 (countdown: remaining/total, stopwatch: loops every 60s)
    var progress: Double {
        switch mode {
        case .countdown:
            guard countdownDuration > 0 else { return 0 }
            return displayTime / countdownDuration
        case .stopwatch:
            return (elapsedTime.truncatingRemainder(dividingBy: 60)) / 60
        }
    }

    /// Formatted time string "MM:SS" or "HH:MM:SS"
    var formattedTime: String {
        let total = Int(displayTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Short format for compact view
    var shortFormattedTime: String {
        let total = Int(displayTime)
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Color for the progress ring
    var stateColor: Color {
        switch state {
        case .idle: return .gray
        case .running: return .green
        case .paused: return .yellow
        case .finished: return .red
        }
    }

    var isActive: Bool {
        state == .running || state == .paused
    }

    // MARK: - Private

    private var elapsedTime: TimeInterval = 0
    private var startDate: Date?
    private var accumulatedTime: TimeInterval = 0
    private var timer: Timer?

    // MARK: - Actions

    func start() {
        guard state == .idle || state == .finished else { return }
        elapsedTime = 0
        accumulatedTime = 0
        startDate = Date()

        if mode == .countdown {
            displayTime = countdownDuration
        } else {
            displayTime = 0
        }

        state = .running
        startTimer()
    }

    func resume() {
        guard state == .paused else { return }
        startDate = Date()
        state = .running
        startTimer()
    }

    func pause() {
        guard state == .running else { return }
        accumulatedTime = elapsedTime
        startDate = nil
        state = .paused
        stopTimer()
    }

    func toggleStartPause() {
        switch state {
        case .idle, .finished:
            start()
        case .running:
            pause()
        case .paused:
            resume()
        }
    }

    func reset() {
        stopTimer()
        elapsedTime = 0
        accumulatedTime = 0
        startDate = nil
        state = .idle
        displayTime = mode == .countdown ? countdownDuration : 0
    }

    func setMode(_ newMode: TimerMode) {
        guard state == .idle || state == .finished else { return }
        mode = newMode
        reset()
    }

    func adjustDuration(by delta: TimeInterval) {
        guard state == .idle || state == .finished else { return }
        countdownDuration = max(60, countdownDuration + delta) // Minimum 1 minute
        displayTime = countdownDuration
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .running, let start = startDate else { return }

        elapsedTime = accumulatedTime + Date().timeIntervalSince(start)

        switch mode {
        case .stopwatch:
            displayTime = elapsedTime

        case .countdown:
            let remaining = countdownDuration - elapsedTime
            if remaining <= 0 {
                displayTime = 0
                finish()
            } else {
                displayTime = remaining
            }
        }
    }

    private func finish() {
        stopTimer()
        state = .finished
        NSSound.beep()

        // Show the notch panel with notification
        NotchViewModel.shared.expand()
    }
}
