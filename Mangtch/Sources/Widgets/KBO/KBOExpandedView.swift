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
            HStack(spacing: 8) {
                statusBadge(game)

                // Teams + score block, aligned around the score
                HStack(spacing: 6) {
                    Text(game.awayTeamName)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(scoreText(game))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(scoreColor(game))
                        .frame(width: 44)
                    Text(game.homeTeamName)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                statusText(game)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(_ game: KBOGame) -> some View {
        Group {
            if game.isLive {
                Circle().fill(.red).frame(width: 7, height: 7)
            } else if game.isFinished {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 7, height: 7)
            } else {
                Circle().fill(.secondary.opacity(0.4)).frame(width: 7, height: 7)
            }
        }
    }

    private func scoreText(_ game: KBOGame) -> String {
        if game.cancel { return "취소" }
        if game.isScheduled { return "vs" }
        return "\(game.awayTeamScore)-\(game.homeTeamScore)"
    }

    private func scoreColor(_ game: KBOGame) -> Color {
        if game.isLive { return .primary }
        if game.isScheduled { return .secondary }
        return .primary
    }

    @ViewBuilder
    private func statusText(_ game: KBOGame) -> some View {
        if game.cancel {
            Text("취소").font(.system(size: 10)).foregroundStyle(.secondary)
        } else if game.isLive {
            HStack(spacing: 4) {
                Text(game.statusInfo).font(.system(size: 10, weight: .medium))
                Text("LIVE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.red, in: Capsule())
            }
        } else if game.isFinished {
            Text("종료").font(.system(size: 10)).foregroundStyle(.secondary)
        } else {
            Text(game.startTimeText).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
