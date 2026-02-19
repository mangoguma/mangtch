import SwiftUI

struct DownloadExpandedView: View {
    let viewModel: DownloadViewModel
    @ObservedObject private var themeEngine = ThemeEngine.shared

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("Downloads")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(themeEngine.currentTheme.textPrimary)
                Spacer()
                if viewModel.hasActiveDownloads {
                    Text("\(viewModel.activeCount) active")
                        .font(.system(size: 11))
                        .foregroundStyle(themeEngine.currentTheme.textSecondary)
                }
            }

            if viewModel.activeDownloads.isEmpty {
                // Empty state
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(themeEngine.currentTheme.textSecondary)
                    Text("No active downloads")
                        .font(.system(size: 11))
                        .foregroundStyle(themeEngine.currentTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                // Download list
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(viewModel.activeDownloads) { download in
                            downloadRow(download)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func downloadRow(_ download: DownloadInfo) -> some View {
        VStack(spacing: 4) {
            HStack {
                // File icon
                Image(systemName: download.isComplete ? "checkmark.circle.fill" : "doc.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(download.isComplete ? .green : .blue)

                // File name
                Text(cleanFileName(download.fileName))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(themeEngine.currentTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Size + speed
                VStack(alignment: .trailing, spacing: 1) {
                    Text(download.formattedSize)
                        .font(.system(size: 9, design: .rounded))
                        .monospacedDigit()
                    if !download.isComplete && !download.speed.isEmpty {
                        Text(download.speed)
                            .font(.system(size: 8, design: .rounded))
                    }
                }
                .foregroundStyle(themeEngine.currentTheme.textSecondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(themeEngine.currentTheme.hudSliderTrackColor)
                        .frame(height: 3)

                    Capsule()
                        .fill(download.isComplete ? Color.green : Color.blue)
                        .frame(width: max(0, geo.size.width * download.progress), height: 3)
                        .animation(.linear(duration: 0.5), value: download.progress)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(themeEngine.currentTheme.backgroundSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cleanFileName(_ name: String) -> String {
        // Remove download extension to show actual file name
        let extensions = ["crdownload", "download", "part", "tmp"]
        var result = name
        for ext in extensions {
            if result.hasSuffix(".\(ext)") {
                result = String(result.dropLast(ext.count + 1))
                break
            }
        }
        return result
    }
}
