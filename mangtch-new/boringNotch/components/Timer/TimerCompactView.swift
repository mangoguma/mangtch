import SwiftUI

struct TimerCompactView: View {
    let viewModel: TimerViewModel

    var body: some View {
        HStack(spacing: TimerLayoutTokens.compactRowSpacing) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: TimerLayoutTokens.compactRingStroke)

                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        viewModel.stateColor,
                        style: StrokeStyle(lineWidth: TimerLayoutTokens.compactRingStroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: viewModel.progress)

                // Mode icon
                Image(systemName: viewModel.mode == .countdown ? "timer" : "stopwatch")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(viewModel.stateColor)
            }
            .frame(width: TimerLayoutTokens.compactRingSize,
                   height: TimerLayoutTokens.compactRingSize)

            // Time display
            if viewModel.isActive || viewModel.state == .finished {
                Text(viewModel.shortFormattedTime)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(viewModel.state == .finished
                        ? viewModel.stateColor
                        : .primary)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.25), value: viewModel.shortFormattedTime)
            } else {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, TimerLayoutTokens.compactHorizontalPadding)
        .padding(.vertical, TimerLayoutTokens.compactVerticalPadding)
        .contentShape(Rectangle())
    }
}
