import SwiftUI

@MainActor
final class TimerWidget: NotchWidget {
    let id = "timer"
    let displayName = "Timer"
    let icon = "timer"
    var isEnabled: Bool = true

    /// Highest priority among current widgets. The user explicitly started
    /// a countdown — that's the most foreground intent, outranks both KBO
    /// live and Music playback.
    let wingPriority: Int = 20

    /// Claim only while the clock is actually running, or right after it
    /// just finished (so the user gets the visual hand-off cue). A user
    /// who's just setting up a countdown — picking a duration via the
    /// numpad — has `displayTime > 0` but `isActive == false`; that
    /// shouldn't grab the wings away from Music/KBO.
    @MainActor
    var claimsWings: Bool {
        viewModel.isActive || viewModel.state == .finished
    }

    let viewModel = TimerViewModel()

    /// State-aware: closed/hovering snap to a compact wing width matching
    /// the small ring + countdown digits, opening jumps to the global
    /// panel canvas (640) for the timer's expanded UI (toggle + 90pt
    /// dial + numpad row). Resting timer wings used to inherit the full
    /// 640pt panel which dominated the menu bar; halving them mirrors
    /// the Music compact treatment.
    var widthRange: WidthRange {
        WidthRange(min: TimerLayoutTokens.compactMinWidth,
                   ideal: TimerLayoutTokens.compactWidth,
                   max: LayoutTokens.panelMaxWidth)
    }
    var heightRange: HeightRange {
        HeightRange(min: TimerLayoutTokens.panelMinHeight,
                    ideal: TimerLayoutTokens.panelIdealHeight,
                    max: TimerLayoutTokens.panelMaxHeight)
    }

    @MainActor
    func makeLeftWingView() -> AnyView {
        AnyView(TimerLeftWing(viewModel: viewModel))
    }

    @MainActor
    func makeRightWingView() -> AnyView {
        AnyView(TimerRightWing(viewModel: viewModel))
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(TimerExpandedView(viewModel: viewModel))
    }

    func activate() {}
    func deactivate() {
        // Don't reset timer on deactivate — user might want it running
    }
}

// MARK: - Compact left-wing: progress ring + mode icon

/// Mirrors the leading half of the legacy `TimerCompactView` HStack: the
/// circular progress ring with the mode icon (`timer`/`stopwatch`)
/// overlaid at center. Trailing chrome (countdown digits) lives in
/// `TimerRightWing` so the priority-chain owner spans both wings.
struct TimerLeftWing: View {
    let viewModel: TimerViewModel

    var body: some View {
        ZStack {
            Circle()
                .stroke(TimerThemeTokens.compactRingTrack,
                        lineWidth: TimerLayoutTokens.compactRingStroke)

            Circle()
                .trim(from: 0, to: viewModel.progress)
                .stroke(
                    viewModel.stateColor,
                    style: StrokeStyle(lineWidth: TimerLayoutTokens.compactRingStroke,
                                       lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: viewModel.progress)

            Image(systemName: viewModel.mode == .countdown ? "timer" : "stopwatch")
                .font(TypographyTokens.microSemibold)
                .foregroundStyle(viewModel.stateColor)
        }
        .frame(width: TimerLayoutTokens.compactRingSize,
               height: TimerLayoutTokens.compactRingSize)
        .padding(.horizontal, TimerLayoutTokens.compactHorizontalPadding)
        .padding(.vertical, TimerLayoutTokens.compactVerticalPadding)
    }
}

// MARK: - Compact right-wing: countdown digits

/// Trailing wing — countdown digits when running/finished, or a
/// `timer` glyph as the idle placeholder. Mirrors the trailing branch
/// of the legacy `TimerCompactView`.
struct TimerRightWing: View {
    let viewModel: TimerViewModel

    var body: some View {
        Group {
            if viewModel.isActive || viewModel.state == .finished {
                Text(viewModel.shortFormattedTime)
                    .font(TypographyTokens.timerCompact)
                    .monospacedDigit()
                    .foregroundStyle(viewModel.state == .finished
                        ? viewModel.stateColor
                        : .primary)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.25), value: viewModel.shortFormattedTime)
            } else {
                Image(systemName: "timer")
                    .font(TypographyTokens.timerCompactLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, TimerLayoutTokens.compactHorizontalPadding)
        .padding(.vertical, TimerLayoutTokens.compactVerticalPadding)
    }
}
