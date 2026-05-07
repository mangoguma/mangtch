import SwiftUI

struct TimerExpandedView: View {
    let viewModel: TimerViewModel

    // Hard-coded dark-panel palette (replaces Mangtch's ThemeManager).
    private let accentColor: Color = .accentColor
    private let textSecondary: Color = .secondary
    private let textPrimary: Color = .primary
    private let backgroundSecondary: Color = Color(white: 0.22)
    private let trackColor: Color = Color(white: 0.28)

    var body: some View {
        VStack(spacing: 16) {
            // Mode selector
            modePicker

            // Main time display with progress ring
            timeDisplay

            // Controls
            controlButtons
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
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
        HStack(spacing: 16) {
            // Duration adjustment (countdown only, when idle)
            if viewModel.mode == .countdown && !viewModel.isActive && viewModel.state != .finished {
                Button(action: { viewModel.adjustDuration(by: -60) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(backgroundSecondary.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(textSecondary)
            }

            // Progress ring + time
            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: 4)

                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        viewModel.stateColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: viewModel.progress)

                Text(viewModel.formattedTime)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(textPrimary)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.25), value: viewModel.formattedTime)
            }
            .frame(width: 90, height: 90)

            // Duration adjustment (countdown only, when idle)
            if viewModel.mode == .countdown && !viewModel.isActive && viewModel.state != .finished {
                Button(action: { viewModel.adjustDuration(by: 60) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
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
        HStack(spacing: 12) {
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
                    ? .yellow
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
