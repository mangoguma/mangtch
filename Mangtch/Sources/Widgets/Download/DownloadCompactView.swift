import SwiftUI

struct DownloadCompactView: View {
    let viewModel: DownloadViewModel
    @ObservedObject private var themeEngine = ThemeEngine.shared

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.hasActiveDownloads {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(themeEngine.currentTheme.hudSliderTrackColor, lineWidth: 2.5)

                    Circle()
                        .trim(from: 0, to: viewModel.totalProgress)
                        .stroke(
                            Color.blue,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: viewModel.totalProgress)

                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.blue)
                }
                .frame(width: 22, height: 22)

                // Download count + percentage
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(viewModel.activeCount) download\(viewModel.activeCount == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(themeEngine.currentTheme.textPrimary)

                    Text("\(Int(viewModel.totalProgress * 100))%")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(themeEngine.currentTheme.textSecondary)
                }
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(themeEngine.currentTheme.textSecondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
