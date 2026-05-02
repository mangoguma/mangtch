import SwiftUI
import AppKit

/// Expanded panel content: KBO games for the displayed day. Default day
/// is today; users can step backward/forward via header chevrons.
struct KBOExpandedView: View {
    let viewModel: KBOViewModel
    @ObservedObject private var themeManager = ThemeManager.shared

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
                // Bare VStack — no ScrollView wrapper. Five games + one
                // expanded row fit naturally inside the panel, and a
                // ScrollView would defeat the dynamic-height measurement
                // below (it reports the available space, not content size).
                VStack(spacing: 4) {
                    ForEach(viewModel.games) { game in
                        gameRow(game)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear {
            // Always re-anchor to today when the widget reopens, so a
            // user who browsed back through the days isn't stuck on an
            // old date the next time they expand the panel.
            viewModel.resetToToday()
            viewModel.recomputePanelHeight()
        }
        .onChange(of: viewModel.games.count) { _, _ in viewModel.recomputePanelHeight() }
        .onChange(of: viewModel.viewingGameID) { _, _ in viewModel.recomputePanelHeight() }
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

                Text(viewModel.isShowingToday
                     ? "오늘"
                     : Self.dateFormatter.string(from: viewModel.displayedDate))
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
        // "isPinned" = the game is currently fixed to the left wing.
        // "isExpanded" = the row is opened to show the inline box score.
        // The two are independent: tapping the row toggles expansion,
        // tapping the pin icon toggles the wing pin.
        let isPinned = viewModel.selectedGameID == game.gameId
        let isExpanded = viewModel.viewingGameID == game.gameId
        // Per-row batting indicator. Only resolves when we have a live
        // state for this game; finished/scheduled rows leave both sides
        // false so the colour falls through to the loser/primary path.
        let attacking = game.isLive ? viewModel.liveStates[game.gameId]?.attackingSide : nil

        VStack(spacing: 0) {
            // Header strip — clickable area that toggles expansion.
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    viewModel.toggleExpand(game)
                }
            }) {
                HStack(spacing: 10) {
                    teamSide(name: game.awayTeamName,
                             code: game.awayTeamCode,
                             logoURL: game.awayEmblemURL,
                             alignment: .trailing,
                             isLoser: game.winnerSide == .home,
                             isBatting: attacking == .away)

                    scoreColumn(game)
                        .frame(width: 64)

                    teamSide(name: game.homeTeamName,
                             code: game.homeTeamCode,
                             logoURL: game.homeEmblemURL,
                             alignment: .leading,
                             isLoser: game.winnerSide == .away,
                             isBatting: attacking == .home)

                    liveStateCell(for: game)
                        .frame(width: 80)

                    statusChip(game)
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inline box score / placeholder, visible only when expanded.
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)
                inlineDetail(game)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowFill(isPinned: isPinned, isExpanded: isExpanded, isLive: game.isLive))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(rowStroke(isPinned: isPinned, isExpanded: isExpanded, isLive: game.isLive),
                              lineWidth: (isPinned || isExpanded) ? 1.2 : 0.5)
        }
        .opacity(game.cancel ? 0.55 : 1)
    }

    // MARK: - Row Sub-views

    @ViewBuilder
    private func teamSide(name: String,
                          code: String,
                          logoURL: URL?,
                          alignment: HorizontalAlignment,
                          isLoser: Bool,
                          isBatting: Bool) -> some View {
        let isLeading = alignment == .leading
        HStack(spacing: 6) {
            if isLeading {
                KBOTeamLogo(url: logoURL, teamCode: code, size: 22)
            }
            Text(name)
                // Bat side gets an underline rather than a colour shift —
                // the row already mixes accent (pinned), red (LIVE chip),
                // and primary text, so adding another red would muddy
                // the hierarchy. Loser dimming still applies independently.
                .font(.system(size: 11.5, weight: isBatting ? .bold : .semibold))
                .lineLimit(1)
                .foregroundStyle(isLoser ? Color.secondary : Color.primary)
                .underline(isBatting, color: isLoser ? .secondary : .primary)
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

    /// Inline at-bat readout (diamond + count + outs). Shown for every
    /// live game we have a `liveStates` entry for — not just the tracked
    /// one — so users can read all in-flight games' bases/count at a
    /// glance. The 80pt slot stays reserved on every row so the columns
    /// don't reflow when state appears or clears mid-row.
    @ViewBuilder
    private func liveStateCell(for game: KBOGame) -> some View {
        if game.isLive, let state = viewModel.liveStates[game.gameId] {
            KBOLiveStateView(state: state, compact: true)
        } else {
            Color.clear
        }
    }

    private func chipText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    // MARK: - Row Background

    private func rowFill(isPinned: Bool, isExpanded: Bool, isLive: Bool) -> Color {
        if isPinned { return Color.accentColor.opacity(0.16) }
        if isExpanded { return Color.primary.opacity(0.07) }
        if isLive { return Color.red.opacity(0.06) }
        return Color.primary.opacity(0.04)
    }

    private func rowStroke(isPinned: Bool, isExpanded: Bool, isLive: Bool) -> Color {
        if isPinned { return Color.accentColor.opacity(0.55) }
        if isExpanded { return Color.primary.opacity(0.25) }
        if isLive { return Color.red.opacity(0.25) }
        return Color.primary.opacity(0.06)
    }

    // MARK: - Inline Detail

    @ViewBuilder
    private func inlineDetail(_ game: KBOGame) -> some View {
        if let line = viewModel.viewingLinescore {
            if line.hasInningData {
                linescoreGrid(game: game, line: line)
            } else {
                liveSummaryFallback(game: game)
            }
        } else if viewModel.isLoadingLinescore {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .frame(minHeight: 50)
        } else {
            Text("기록을 가져오지 못했어요")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
    }

    private func liveSummaryFallback(game: KBOGame) -> some View {
        VStack(spacing: 4) {
            Text(game.isLive
                 ? "이닝 기록 준비 중 — 잠시 후 자동으로 표시돼요"
                 : "이닝 기록이 아직 등록되지 않았어요")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
    }

    private func linescoreGrid(game: KBOGame, line: KBOLinescore) -> some View {
        let cols = line.innings
        return VStack(spacing: 0) {
            scoreRow(team: "팀명",
                     innings: (1...cols).map { String($0) },
                     totals: ["R", "H", "E", "B"],
                     isHeader: true)
                .background(Color.secondary.opacity(0.08))

            scoreRow(team: game.awayTeamName,
                     innings: line.awayInningScores,
                     totals: totalsCells(line.awayTotals),
                     isHeader: false)
            scoreRow(team: game.homeTeamName,
                     innings: line.homeInningScores,
                     totals: totalsCells(line.homeTotals),
                     isHeader: false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.secondary.opacity(0.15), lineWidth: 0.5)
        }
    }

    private func totalsCells(_ t: KBOLinescore.Totals?) -> [String] {
        guard let t else { return ["-", "-", "-", "-"] }
        return [String(t.runs), String(t.hits), String(t.errors), String(t.walks)]
    }

    private func scoreRow(team: String,
                          innings: [String],
                          totals: [String],
                          isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            Text(team)
                .font(.system(size: isHeader ? 9 : 10,
                              weight: isHeader ? .semibold : .medium))
                .foregroundStyle(isHeader ? .secondary : .primary)
                .lineLimit(1)
                .frame(width: 44, alignment: .leading)

            // Static row — innings always fit horizontally in the panel
            // (worst case 12 innings × 20pt = 240pt; usable width is ~430pt).
            // No inner scroll so users see the whole frame at once.
            HStack(spacing: 0) {
                ForEach(innings.indices, id: \.self) { i in
                    Text(innings[i])
                        .font(.system(size: isHeader ? 9 : 11,
                                      weight: .semibold,
                                      design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isHeader ? .secondary : .primary)
                        .frame(width: 20, height: 20)
                }
            }

            HStack(spacing: 0) {
                ForEach(totals.indices, id: \.self) { i in
                    Text(totals[i])
                        .font(.system(size: isHeader ? 9 : 11,
                                      weight: .bold,
                                      design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isHeader
                                         ? Color.accentColor
                                         : (i == 0 ? .primary : .secondary))
                        .frame(width: 22, height: 20)
                }
            }
            .padding(.leading, 4)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.secondary.opacity(0.15))
                    .frame(width: 0.5)
                    .padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 6)
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
