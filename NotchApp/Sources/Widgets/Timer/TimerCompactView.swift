import SwiftUI

struct TimerCompactView: View {
    let viewModel: TimerViewModel
    @ObservedObject private var themeEngine = ThemeEngine.shared

    var body: some View {
        HStack(spacing: 8) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(themeEngine.currentTheme.hudSliderTrackColor, lineWidth: 2.5)

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
            .frame(width: 22, height: 22)

            // Time display
            if viewModel.isActive || viewModel.state == .finished {
                Text(viewModel.shortFormattedTime)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(viewModel.state == .finished
                        ? viewModel.stateColor
                        : themeEngine.currentTheme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.25), value: viewModel.shortFormattedTime)
            } else {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(themeEngine.currentTheme.textSecondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
