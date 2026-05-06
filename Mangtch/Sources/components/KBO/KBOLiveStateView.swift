import SwiftUI

/// Right-wing host: shows the live state pill while a live game is
/// pinned, the latest play ticker overlay when one's in flight, and a
/// quiet placeholder otherwise.
struct KBORightWingContainer: View {
    let viewModel: KBOViewModel

    var body: some View {
        if let state = viewModel.currentLiveState,
           let game = viewModel.selectedGame, game.isLive {
            // Pitcher is on the defending side, batter on the attacking
            // side. attackingSide is nil between innings / before first
            // pitch — leave both colours nil so the chips fall back to
            // the neutral disc rather than guessing.
            let homeColor = KBOTeamColors.primary(for: game.homeTeamCode)
            let awayColor = KBOTeamColors.primary(for: game.awayTeamCode)
            let (pColor, bColor): (Color?, Color?) = {
                switch state.attackingSide {
                case .home: return (awayColor, homeColor)
                case .away: return (homeColor, awayColor)
                case .none: return (nil, nil)
                }
            }()
            KBOLiveStateView(state: state,
                             playText: viewModel.latestPlayText,
                             pitcherTeamColor: pColor,
                             batterTeamColor: bColor)
        } else {
            Image(systemName: "baseball")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

/// Right-wing live at-bat readout: a small bases diamond plus a
/// "B-S, N out" count line. Replaces the song info on the right wing
/// while a KBO live game is pinned, since runners and count are the
/// signal-densest thing the broadcast updates pitch-by-pitch.
struct KBOLiveStateView: View {
    let state: KBOLinescore.LiveState
    /// Compact form for the in-row position alongside the status chip:
    /// drops the dot rings and shows "B-S · O out" inline next to a smaller
    /// diamond. Default form is the wing-sized vertical layout.
    var compact: Bool = false
    /// Latest play commentary. When non-nil, replaces the pitcher/batter
    /// column with a horizontally-scrolling marquee so the user reads the
    /// play outcome without losing the diamond/count context.
    var playText: String? = nil
    /// Primary club colour for the side currently pitching / batting.
    /// nil falls back to a neutral fill so a missing attackingSide doesn't
    /// render as an unrelated team's colour. Resolved at the call site
    /// because the view doesn't have access to KBOGame's team codes.
    var pitcherTeamColor: Color? = nil
    var batterTeamColor: Color? = nil

    var body: some View {
        if compact { compactBody } else { wingBody }
    }

    private var compactBody: some View {
        HStack(spacing: 5) {
            BasesDiamond(onFirst: state.onFirst,
                         onSecond: state.onSecond,
                         onThird: state.onThird)
                .frame(width: 18, height: 18)

            Text("\(state.balls)-\(state.strikes)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            // Outs as filled red dots (0..2), matching the wing form.
            // Numeric "2O" reads as a count; the dot row matches the
            // broadcast convention so it's instantly recognisable.
            compactOutsDots(value: state.outs)
        }
    }

    private func compactOutsDots(value: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { i in
                let isFilled = i < value
                Circle()
                    .fill(isFilled ? Color.red : Color.clear)
                    .overlay(
                        Circle().strokeBorder(
                            isFilled ? Color.red : Color.secondary.opacity(0.6),
                            lineWidth: 0.8
                        )
                    )
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var wingBody: some View {
        // Three columns: diamond | B/S/O dots | pitcher/batter names.
        // Stretches to fill the full wing width so the right side doesn't
        // sit empty when names are present.
        HStack(spacing: 6) {
            BasesDiamond(onFirst: state.onFirst,
                         onSecond: state.onSecond,
                         onThird: state.onThird)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 0) {
                countRow(value: state.balls, total: 3, label: "B", filledColor: .green)
                countRow(value: state.strikes, total: 2, label: "S", filledColor: .yellow)
                countRow(value: state.outs, total: 2, label: "O", filledColor: .red)
            }

            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 1) {
                    playerRow(icon: "p.circle.fill",
                              name: state.pitcherName,
                              tint: pitcherTeamColor)
                    playerRow(icon: "b.circle.fill",
                              name: state.batterName,
                              order: state.batOrder,
                              tint: batterTeamColor)
                }
                .opacity(playText == nil ? 1 : 0)

                if let playText {
                    MarqueeText(playText,
                                font: .system(size: 10, weight: .medium),
                                speed: 28,
                                isActive: true)
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: playText)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No inner pill — the wing's own dark panel background already
        // provides the contrast surface. An extra rounded rect inside it
        // would visibly disagree with the wing's edge curvature.
    }

    private func countRow(value: Int, total: Int, label: String, filledColor: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 8, alignment: .center)
            countDots(value: value, total: total, filledColor: filledColor)
        }
    }

    /// "P 박세웅" / "B 3 박승규" — order shown only for the batter, since
    /// pitcher batting order is meaningless. Falls back to "—" when the
    /// lineup lookup didn't resolve a name.
    private func playerRow(icon: String, name: String?, order: Int? = nil, tint: Color? = nil) -> some View {
        // Palette rendering paints the disc in the team colour while the
        // letter glyph stays white — the conventional "club badge" look.
        // Falls back to a flat white symbol when no tint resolved (e.g.
        // attackingSide unknown), preserving the prior appearance.
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, tint ?? .secondary)
            if let order {
                Text("\(order)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(name ?? "—")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Filled active dots use the per-row colour (green for balls, yellow
    /// for strikes, red for outs); unused slots stay as a hollow black ring
    /// so the row still reads on the light wing background.
    private func countDots(value: Int, total: Int, filledColor: Color) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                let isFilled = i < value
                Circle()
                    .fill(isFilled ? filledColor : Color.clear)
                    .overlay(
                        Circle().strokeBorder(
                            isFilled ? filledColor : Color.white.opacity(0.7),
                            lineWidth: 0.8
                        )
                    )
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// Top-down baseball diamond. 2nd at top, 1st at right, 3rd at left,
/// home implied at the bottom (omitted — the catcher is never the story).
/// Filled when a runner stands on that base.
private struct BasesDiamond: View {
    let onFirst: Bool
    let onSecond: Bool
    let onThird: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let baseSize: CGFloat = s * 0.34
            ZStack {
                // 2nd (top center)
                base(filled: onSecond, size: baseSize)
                    .position(x: s / 2, y: baseSize * 0.6)
                // 3rd (left)
                base(filled: onThird, size: baseSize)
                    .position(x: baseSize * 0.6, y: s / 2)
                // 1st (right)
                base(filled: onFirst, size: baseSize)
                    .position(x: s - baseSize * 0.6, y: s / 2)
            }
        }
    }

    private func base(filled: Bool, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(filled ? Color.yellow : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .strokeBorder(filled ? Color.yellow : Color.white.opacity(0.7), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(45))
    }
}
