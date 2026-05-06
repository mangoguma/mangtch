import SwiftUI

struct TimerCompactView: View {
    let viewModel: TimerViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2.5)

                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        viewModel.stateColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: viewModel.progress)

                // Mode icon
                Image(systemName: viewModel.mode == .countdown ? "timer" : "stopwatch")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(viewModel.stateColor)
            }
            .frame(width: 18, height: 18)

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
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
