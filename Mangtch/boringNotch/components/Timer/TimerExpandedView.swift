import SwiftUI

struct TimerExpandedView: View {
    let viewModel: TimerViewModel

    // Hard-coded dark-panel palette (replaces Mangtch's ThemeManager).
    private let accentColor: Color = .accentColor
    private let textSecondary: Color = .secondary
    private let textPrimary: Color = .primary
    private let backgroundSecondary: Color = TimerThemeTokens.surfaceMedium
    private let trackColor: Color = TimerThemeTokens.trackBackground

    var body: some View {
        VStack(spacing: TimerLayoutTokens.expandedSpacing) {
            // Mode selector
            modePicker

            // Main time display with progress ring
            timeDisplay

            // Controls
            controlButtons
        }
        .padding(.horizontal, TimerLayoutTokens.expandedHorizontalPadding)
        .padding(.vertical, TimerLayoutTokens.expandedVerticalPadding)
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(TimerMode.allCases, id: \.rawValue) { mode in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.setMode(mode)
                    }
                }) {
                    Text(mode.rawValue)
                        .font(TypographyTokens.expandedBody)
                        .padding(.horizontal, TimerLayoutTokens.modePillHorizontalPadding)
                        .padding(.vertical, TimerLayoutTokens.modePillVerticalPadding)
                        .background(
                            viewModel.mode == mode
                                ? accentColor.opacity(0.2)
                                : Color.clear
                        )
                        .foregroundStyle(
                            viewModel.mode == mode
                                ? accentColor
                                : textSecondary
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isActive)
            }
        }
        .background(backgroundSecondary.opacity(0.5))
        .clipShape(Capsule())
    }

    // MARK: - Time Display

    private var timeDisplay: some View {
        HStack(spacing: TimerLayoutTokens.timeDisplaySpacing) {
            // Duration adjustment (countdown only, when idle)
            if viewModel.mode == .countdown && !viewModel.isActive && viewModel.state != .finished {
                Button(action: { viewModel.adjustDuration(by: -60) }) {
                    Image(systemName: "minus")
                        .font(TypographyTokens.timerControl)
                        .frame(width: TimerLayoutTokens.adjustButtonSize,
                               height: TimerLayoutTokens.adjustButtonSize)
                        .background(backgroundSecondary.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(textSecondary)
            }

            // Progress ring + time
            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: TimerLayoutTokens.progressRingStroke)

                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        viewModel.stateColor,
                        style: StrokeStyle(lineWidth: TimerLayoutTokens.progressRingStroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: viewModel.progress)

                Text(viewModel.formattedTime)
                    .font(TypographyTokens.timerDisplay)
                    .monospacedDigit()
                    .foregroundStyle(textPrimary)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.25), value: viewModel.formattedTime)
            }
            .frame(width: TimerLayoutTokens.progressRingSize,
                   height: TimerLayoutTokens.progressRingSize)

            // Duration adjustment (countdown only, when idle)
            if viewModel.mode == .countdown && !viewModel.isActive && viewModel.state != .finished {
                Button(action: { viewModel.adjustDuration(by: 60) }) {
                    Image(systemName: "plus")
                        .font(TypographyTokens.timerControl)
                        .frame(width: TimerLayoutTokens.adjustButtonSize,
                               height: TimerLayoutTokens.adjustButtonSize)
                        .background(backgroundSecondary.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(textSecondary)
            }
        }
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: TimerLayoutTokens.actionRowSpacing) {
            // Reset
            if viewModel.isActive || viewModel.state == .finished {
                actionButton(
                    icon: "arrow.counterclockwise",
                    label: "Reset",
                    color: textSecondary
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.reset()
                    }
                }
            }

            // Start / Pause / Resume
            actionButton(
                icon: startPauseIcon,
                label: startPauseLabel,
                color: viewModel.state == .running
                    ? TimerThemeTokens.pausedAccent
                    : accentColor
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleStartPause()
                }
            }
        }
    }

    private var startPauseIcon: String {
        switch viewModel.state {
        case .running: return "pause.fill"
        case .paused: return "play.fill"
        default: return "play.fill"
        }
    }

    private var startPauseLabel: String {
        switch viewModel.state {
        case .running: return "Pause"
        case .paused: return "Resume"
        default: return "Start"
        }
    }

    private func actionButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TimerLayoutTokens.actionButtonInternalSpacing) {
                Image(systemName: icon)
                    .font(TypographyTokens.timerLabel)
                Text(label)
                    .font(TypographyTokens.timerLabel)
            }
            .padding(.horizontal, TimerLayoutTokens.actionButtonHorizontalPadding)
            .padding(.vertical, TimerLayoutTokens.actionButtonVerticalPadding)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
