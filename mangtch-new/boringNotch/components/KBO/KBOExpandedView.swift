import SwiftUI
import AppKit

/// Expanded panel content: KBO games for the displayed day. Default day
/// is today; users can step backward/forward via header chevrons.
struct KBOExpandedView: View {
    let viewModel: KBOViewModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()

    private static let naverScheduleURL = URL(string: "https://m.sports.naver.com/kbaseball/schedule/index")!

    var body: some View {
        VStack(alignment: .leading, spacing: KBOLayoutTokens.bodyOuterSpacing) {
            header

            if viewModel.games.isEmpty {
                emptyState
            } else {
                // Bare VStack — no ScrollView wrapper. Five games + one
                // expanded row fit naturally inside the panel, and a
                // ScrollView would defeat the dynamic-height measurement
                // below (it reports the available space, not content size).
                VStack(spacing: KBOLayoutTokens.rowGap) {
                    ForEach(viewModel.games) { game in
                        gameRow(game)
                    }
                }
            }
        }
        .padding(.horizontal, KBOLayoutTokens.bodyOuterHorizontalPadding)
        .padding(.vertical, KBOLayoutTokens.bodyOuterVerticalPadding)
        .onAppear {
            // Re-anchor the date to today on reopen, but keep any
            // expanded row / pinned game intact so the live broadcast
            // the user was watching survives close/reopen.
            viewModel.rewindDateOnly()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: KBOLayoutTokens.headerSpacing) {
            Label("KBO", systemImage: "baseball")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            // Day navigation: ‹ date › with a "오늘" reset when off today.
            HStack(spacing: KBOLayoutTokens.headerDayNavSpacing) {
                Button { viewModel.shiftDay(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: KBOLayoutTokens.headerChevronSize,
                               height: KBOLayoutTokens.headerChevronSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(viewModel.isShowingToday
                     ? "오늘"
                     : Self.dateFormatter.string(from: viewModel.displayedDate))
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: KBOLayoutTokens.headerDateMinWidth)

                Button { viewModel.shiftDay(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: KBOLayoutTokens.headerChevronSize,
                               height: KBOLayoutTokens.headerChevronSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Keep the button slot reserved even when on "today" so the
            // surrounding buttons don't reflow horizontally as the user
            // steps days. Fade + disable instead of conditional insertion.
            Button("오늘") { viewModel.resetToToday() }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .opacity(viewModel.isShowingToday ? 0 : 1)
                .allowsHitTesting(!viewModel.isShowingToday)

            // Jump out to Naver Sports for the full schedule view.
            Button {
                NSWorkspace.shared.open(Self.naverScheduleURL)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .frame(width: KBOLayoutTokens.headerChevronSize,
                           height: KBOLayoutTokens.headerChevronSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("네이버 스포츠에서 보기")

            // Same reserved-slot trick — a popping ProgressView would
            // shove the whole row sideways every fetch.
            ProgressView()
                .controlSize(.mini)
                .opacity(viewModel.isLoading ? 1 : 0)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: KBOLayoutTokens.emptyStateSpacing) {
            Image(systemName: "baseball")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(viewModel.isShowingToday
                 ? "오늘 KBO 경기가 없어요"
                 : "이 날 KBO 경기가 없어요")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: KBOLayoutTokens.emptyStateMinHeight)
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
                HStack(spacing: KBOLayoutTokens.rowChildSpacing) {
                    let starters = viewModel.startingPitchers[game.gameId]
                    let slotW = rowSlotWidth

                    // Left slot: away starter on non-live rows, blank on
                    // live rows (the diamond/count goes on the right slot
                    // so the live read sits next to the home team — same
                    // side Naver puts it on their relay strip).
                    Group {
                        if game.isLive {
                            Color.clear
                        } else {
                            inlineStarterLabel(name: starters?.away,
                                               resultPrefix: resultPrefix(game: game, side: .away),
                                               trailing: false,
                                               slotWidth: slotW)
                        }
                    }
                    .frame(width: slotW)

                    teamSide(name: game.awayTeamName,
                             code: game.awayTeamCode,
                             logoURL: game.awayEmblemURL,
                             alignment: .trailing,
                             isLoser: game.winnerSide == .home,
                             isBatting: attacking == .away)

                    scoreColumn(game)
                        .frame(width: KBOLayoutTokens.scoreColumnWidth)

                    teamSide(name: game.homeTeamName,
                             code: game.homeTeamCode,
                             logoURL: game.homeEmblemURL,
                             alignment: .leading,
                             isLoser: game.winnerSide == .away,
                             isBatting: attacking == .home)

                    // Right slot: live read replaces home starter when
                    // the game is in progress — bases/count is the
                    // single most useful glance for a live game, more so
                    // than a starter who may already be out of the game.
                    Group {
                        if game.isLive {
                            liveStateCell(for: game)
                        } else {
                            inlineStarterLabel(name: starters?.home,
                                               resultPrefix: resultPrefix(game: game, side: .home),
                                               trailing: true,
                                               slotWidth: slotW)
                        }
                    }
                    .frame(width: slotW)

                    statusChip(game)
                        .frame(width: KBOLayoutTokens.statusChipWidth, alignment: .trailing)
                }
                .padding(.horizontal, KBOLayoutTokens.rowHorizontalPadding)
                .padding(.vertical, KBOLayoutTokens.rowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inline box score / placeholder, visible only when expanded.
            if isExpanded {
                Divider()
                    .padding(.horizontal, KBOLayoutTokens.rowHorizontalPadding)
                inlineDetail(game)
                    .padding(.horizontal, KBOLayoutTokens.rowHorizontalPadding)
                    .padding(.vertical, KBOLayoutTokens.rowVerticalPadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: KBOLayoutTokens.rowCornerRadius, style: .continuous)
                .fill(rowFill(isPinned: isPinned, isExpanded: isExpanded, isLive: game.isLive))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KBOLayoutTokens.rowCornerRadius, style: .continuous)
                .strokeBorder(rowStroke(isPinned: isPinned, isExpanded: isExpanded, isLive: game.isLive),
                              lineWidth: (isPinned || isExpanded)
                                ? KBOLayoutTokens.rowStrokeActive
                                : KBOLayoutTokens.rowStrokeIdle)
        }
        .opacity(game.cancel ? 0.55 : 1)
    }

    // MARK: - Row Sub-views

    /// Width of each row-edge slot. Derived from the longest cached
    /// starter name so 5-char names like "로드리게스" don't crowd the
    /// badge, but bumped up to fit the 80pt live-state cell on rows
    /// where the slot hosts the diamond/BSO instead. Fixed (rather than
    /// flex) so the 승/패 badges align vertically across rows — names
    /// float toward the outer edge while badges stay anchored to the
    /// inner edge of the slot, giving every row a consistent W/L column.
    @MainActor
    private var rowSlotWidth: CGFloat {
        let names = viewModel.startingPitchers.values
            .flatMap { [$0.away, $0.home] }
            .compactMap { $0 }
        let font = NSFont.systemFont(ofSize: KBOLayoutTokens.inlineStarterFontSize,
                                     weight: .semibold)
        let widest = names
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // Name + gap + badge (~12pt for "승/패") + outer breathing
        // room so the badge doesn't kiss the score column.
        let starterNeeded = ceil(widest)
            + KBOLayoutTokens.inlineStarterNameGap
            + KBOLayoutTokens.inlineStarterBadgeWidth
            + KBOLayoutTokens.inlineStarterTrailing
        // rowSlotMinWidth is the natural width of KBOLiveStateView in compact mode.
        return max(KBOLayoutTokens.rowSlotMinWidth, starterNeeded)
    }

    /// Inline starting-pitcher label that sits at the outer edges of the
    /// game row. Just the name plus an optional 승/패 prefix once the
    /// game ends — no badge / "선발" tag, since row context already
    /// implies the pitcher slot. The W/L tag is attributed to the
    /// starter even though the pitcher of record may be a reliever; it
    /// matches Naver's collapsed-card UX and users mainly want a quick
    /// "who pitched / who took the L" read.
    ///
    /// `trailing=false` for the away side: name flush to the inner edge
    /// of the slot, badge tucked just inside it (between name and the
    /// score column). Mirrored on the home side.
    @ViewBuilder
    private func inlineStarterLabel(name: String?,
                                    resultPrefix: String?,
                                    trailing: Bool,
                                    slotWidth: CGFloat) -> some View {
        let inner = HStack(spacing: KBOLayoutTokens.inlineStarterNameGap) {
            if !trailing {
                Spacer(minLength: 0)
                if let name {
                    Text(name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize()
                }
                if let resultPrefix {
                    resultBadge(resultPrefix)
                }
            } else {
                if let resultPrefix {
                    resultBadge(resultPrefix)
                }
                if let name {
                    Text(name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize()
                }
                Spacer(minLength: 0)
            }
        }
        inner.frame(width: slotWidth,
                    alignment: trailing ? .leading : .trailing)
    }

    private func resultBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(text == "승" ? Color.blue : Color.secondary)
    }

    /// "승"/"패" for a finished game's losing/winning side, "선발" for
    /// pre-game / live as a softer tag, and nil when there's nothing
    /// useful to mark (cancelled, no winner / draw).
    private func resultPrefix(game: KBOGame, side: KBOGame.Side) -> String? {
        guard !game.cancel else { return nil }
        if game.isFinished, let winner = game.winnerSide {
            return winner == side ? "승" : "패"
        }
        return nil
    }

    @ViewBuilder
    private func teamSide(name: String,
                          code: String,
                          logoURL: URL?,
                          alignment: HorizontalAlignment,
                          isLoser: Bool,
                          isBatting: Bool) -> some View {
        let isLeading = alignment == .leading
        HStack(spacing: KBOLayoutTokens.teamSideSpacing) {
            if isLeading {
                KBOTeamLogo(url: logoURL, teamCode: code, size: KBOLayoutTokens.teamLogoSize)
            }
            Text(name)
                // Bat side gets an underline rather than a colour shift —
                // the row already mixes accent (pinned), red (LIVE chip),
                // and primary text, so adding another red would muddy
                // the hierarchy. Loser dimming still applies independently.
                .font(.system(size: 11.5, weight: isBatting ? .bold : .semibold))
                .fixedSize()
                .foregroundStyle(isLoser ? Color.secondary : Color.primary)
                .underline(isBatting, color: isLoser ? .secondary : .primary)
            if !isLeading {
                KBOTeamLogo(url: logoURL, teamCode: code, size: KBOLayoutTokens.teamLogoSize)
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
            HStack(spacing: KBOLayoutTokens.scoreSpacing) {
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
            HStack(spacing: KBOLayoutTokens.liveDotSpacing) {
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
            // Scheduled games have no relay payload yet, so the catch-all
            // "기록을 가져오지 못했어요" reads like a network error when
            // really it's just "경기 전이라 아직 기록이 없음". Branch the
            // copy so users don't think something's broken.
            Text(preGameOrErrorMessage(for: game))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
    }

    private func preGameOrErrorMessage(for game: KBOGame) -> String {
        if game.cancel { return "경기가 취소됐어요" }
        if game.isScheduled {
            return "\(game.startTimeText) 경기 시작 전이라 아직 기록이 없어요"
        }
        return "기록을 가져오지 못했어요"
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
        let grid = VStack(spacing: 0) {
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
        .clipShape(RoundedRectangle(cornerRadius: KBOLayoutTokens.linescoreCornerRadius,
                                    style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KBOLayoutTokens.linescoreCornerRadius,
                             style: .continuous)
                .strokeBorder(.secondary.opacity(0.15),
                              lineWidth: KBOLayoutTokens.linescoreDividerWidth)
        }

        // Starting pitchers flank the grid: away on the left (matches the
        // header row's "{away} · {home}" left/right ordering), home on the
        // right. Slot stays reserved even when a name isn't published yet
        // so the grid doesn't jump horizontally once lineups arrive.
        return HStack(alignment: .center, spacing: KBOLayoutTokens.openGridGutter) {
            starterLabel(name: line.awayStartingPitcher,
                         teamCode: game.awayTeamCode,
                         alignment: .leading)
            grid
            starterLabel(name: line.homeStartingPitcher,
                         teamCode: game.homeTeamCode,
                         alignment: .trailing)
        }
    }

    private func starterLabel(name: String?,
                              teamCode: String,
                              alignment: HorizontalAlignment) -> some View {
        // Tint the "P" badge with the team colour but keep the name in
        // primary — KT/롯데/두산 colours are nearly black and would vanish
        // against the panel's dark fill if applied to text directly.
        let isLeading = alignment == .leading
        let badge = Image(systemName: "p.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, KBOTeamColors.primary(for: teamCode))
        return VStack(alignment: alignment, spacing: KBOLayoutTokens.expandedStarterRowSpacing) {
            Text("선발")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: KBOLayoutTokens.expandedStarterRowSpacing) {
                if isLeading { badge }
                Text(name ?? "—")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(name == nil ? Color.secondary : Color.primary)
                    .fixedSize()
                if !isLeading { badge }
            }
        }
        // Slot sizes to its actual content — the panel chrome's
        // `widthRange` derivation in `KBOWidget` measures the
        // same name with the same font, so wing/panel widen to fit
        // exactly. No `lineLimit` (CLAUDE.md), no fixed slot width.
        .fixedSize(horizontal: true, vertical: false)
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
                .frame(width: KBOLayoutTokens.linescoreTeamLabelWidth, alignment: .leading)

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
                        .frame(width: KBOLayoutTokens.linescoreInningCellWidth,
                               height: KBOLayoutTokens.linescoreInningCellHeight)
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
                        .frame(width: KBOLayoutTokens.linescoreTotalsCellWidth,
                               height: KBOLayoutTokens.linescoreTotalsCellHeight)
                }
            }
            .padding(.leading, KBOLayoutTokens.linescoreTotalsLeading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.secondary.opacity(0.15))
                    .frame(width: KBOLayoutTokens.linescoreDividerWidth)
                    .padding(.vertical, KBOLayoutTokens.linescoreDividerVerticalPadding)
            }
        }
        .padding(.horizontal, KBOLayoutTokens.linescoreSidePadding)
    }
}

/// 1-1.4× scaling pulse for the LIVE indicator. Subtle — not distracting,
/// but enough to draw the eye to in-progress games among finished/scheduled.
private struct LivePulseDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: KBOLayoutTokens.livePulseDotSize,
                   height: KBOLayoutTokens.livePulseDotSize)
            .scaleEffect(pulse ? 1.35 : 1.0)
            .opacity(pulse ? 0.55 : 1.0)
            .onAppear { pulse = true }
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
    }
}
