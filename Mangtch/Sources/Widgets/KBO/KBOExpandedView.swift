import SwiftUI
import AppKit

/// Expanded panel content: KBO games for the displayed day. Default day
/// is today; users can step backward/forward via header chevrons.
struct KBOExpandedView: View {
    let viewModel: KBOViewModel
    @ObservedObject private var themeEngine = ThemeEngine.shared

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()

    private static let naverScheduleURL = URL(string: "https://m.sports.naver.com/kbaseball/schedule/index")!

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if viewModel.games.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(viewModel.games) { game in
                            gameRow(game)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Label("KBO", systemImage: "baseball")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            // Day navigation: ‹ date › with a "오늘" reset when off today.
            HStack(spacing: 4) {
                Button { viewModel.shiftDay(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(Self.dateFormatter.string(from: viewModel.displayedDate))
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: 80)

                Button { viewModel.shiftDay(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !viewModel.isShowingToday {
                Button("오늘") { viewModel.resetToToday() }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }

            // Jump out to Naver Sports for the full schedule view.
            Button {
                NSWorkspace.shared.open(Self.naverScheduleURL)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("네이버 스포츠에서 보기")

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "baseball")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(viewModel.isShowingToday
                 ? "오늘 KBO 경기가 없어요"
                 : "이 날 KBO 경기가 없어요")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Row

    @ViewBuilder
    private func gameRow(_ game: KBOGame) -> some View {
        let isSelected = viewModel.selectedGameID == game.gameId

        Button(action: { viewModel.select(game) }) {
            HStack(spacing: 10) {
                // Away side
                teamSide(name: game.awayTeamName,
                         code: game.awayTeamCode,
                         logoURL: game.awayEmblemURL,
                         alignment: .trailing,
                         isLoser: game.winnerSide == .home)

                // Score column — fixed width so all rows align vertically
                scoreColumn(game)
                    .frame(width: 64)

                // Home side
                teamSide(name: game.homeTeamName,
                         code: game.homeTeamCode,
                         logoURL: game.homeEmblemURL,
                         alignment: .leading,
                         isLoser: game.winnerSide == .away)

                // Status: LIVE / 종료 / 18:30 / 취소
                statusChip(game)
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(rowFill(isSelected: isSelected, isLive: game.isLive))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(rowStroke(isSelected: isSelected, isLive: game.isLive),
                                  lineWidth: isSelected ? 1.2 : 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(game.cancel ? 0.55 : 1)
    }

    // MARK: - Row Sub-views

    @ViewBuilder
    private func teamSide(name: String,
                          code: String,
                          logoURL: URL?,
                          alignment: HorizontalAlignment,
                          isLoser: Bool) -> some View {
        let isLeading = alignment == .leading
        HStack(spacing: 6) {
            if isLeading {
                KBOTeamLogo(url: logoURL, teamCode: code, size: 22)
            }
            Text(name)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isLoser ? .secondary : .primary)
            if !isLeading {
                KBOTeamLogo(url: logoURL, teamCode: code, size: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
    }

    @ViewBuilder
    private func scoreColumn(_ game: KBOGame) -> some View {
        if game.cancel {
            Text("취소")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        } else if game.isScheduled {
            Text("vs")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                scoreNumber(game.awayTeamScore,
                            isLoser: game.winnerSide == .home)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                scoreNumber(game.homeTeamScore,
                            isLoser: game.winnerSide == .away)
            }
        }
    }

    private func scoreNumber(_ value: Int, isLoser: Bool) -> some View {
        Text("\(value)")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isLoser ? .secondary : .primary)
    }

    @ViewBuilder
    private func statusChip(_ game: KBOGame) -> some View {
        if game.cancel {
            chipText("취소", color: .secondary)
        } else if game.isLive {
            HStack(spacing: 4) {
                LivePulseDot()
                Text(game.statusInfo.isEmpty ? "LIVE" : game.statusInfo)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        } else if game.isFinished {
            chipText("종료", color: .secondary)
        } else {
            chipText(game.startTimeText, color: .secondary)
        }
    }

    private func chipText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    // MARK: - Row Background

    private func rowFill(isSelected: Bool, isLive: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isLive { return Color.red.opacity(0.06) }
        return Color.primary.opacity(0.04)
    }

    private func rowStroke(isSelected: Bool, isLive: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.55) }
        if isLive { return Color.red.opacity(0.25) }
        return Color.primary.opacity(0.06)
    }
}

/// 1-1.4× scaling pulse for the LIVE indicator. Subtle — not distracting,
/// but enough to draw the eye to in-progress games among finished/scheduled.
private struct LivePulseDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 6, height: 6)
            .scaleEffect(pulse ? 1.35 : 1.0)
            .opacity(pulse ? 0.55 : 1.0)
            .onAppear { pulse = true }
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
    }
}
