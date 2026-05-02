import SwiftUI

/// Left-wing compact view for the KBO widget. Renders the live score by
/// default; on hover it swaps to two toggle buttons (ticker on/off, TTS
/// on/off). Clicks themselves are dispatched by GestureHandler — this
/// view is purely visual since SwiftUI gesture recognisers don't fire
/// inside our .nonactivatingPanel.
struct KBOCompactView: View {
    let viewModel: KBOViewModel
    private var notchVM: NotchViewModel { NotchViewModel.shared }

    @State private var pulse = false

    var body: some View {
        if let game = viewModel.selectedGame, game.isLive {
            let isHovering = notchVM.hoveredWing == .left
            ZStack {
                scoreView(game: game)
                    .opacity(isHovering ? 0 : 1)

                hoverToggles
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(isHovering ? 0.18 : 0))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            )
            .animation(.easeInOut(duration: 0.18), value: isHovering)
            .onAppear { pulse = true }
        } else {
            Image(systemName: "baseball")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Score (default)

    private func scoreView(game: KBOGame) -> some View {
        let attacking = viewModel.currentAttackingSide
        let awayBatting = attacking == .away
        let homeBatting = attacking == .home
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                        .opacity(pulse ? 0.5 : 1.0)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                   value: pulse)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.red)
                }
                Text(game.statusInfo.isEmpty ? "—" : game.statusInfo)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 3) {
                teamName(game.awayTeamName, isBatting: awayBatting)
                Text("\(game.awayTeamScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(":")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text("\(game.homeTeamScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                teamName(game.homeTeamName, isBatting: homeBatting)
            }
        }
    }

    /// Team-name label with a small bat marker when that side is at bat.
    /// The marker (and the bolder weight) is the only signal of who's
    /// batting at compact-wing scale, where there's no room for a full
    /// inning-half indicator.
    private func teamName(_ name: String, isBatting: Bool) -> some View {
        HStack(spacing: 2) {
            if isBatting {
                Image(systemName: "figure.baseball")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
            }
            Text(name)
                .font(.system(size: 10, weight: isBatting ? .bold : .medium))
                .foregroundStyle(isBatting ? .primary : .secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Hover toggles

    private var hoverToggles: some View {
        HStack(spacing: 6) {
            toggleIcon(
                isOn: viewModel.tickerEnabled,
                icon: "captions.bubble.fill"
            )
            toggleIcon(
                isOn: viewModel.ttsEnabled,
                icon: "speaker.wave.2.fill"
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Both ON and OFF states render with a filled background pill —
    /// only the colour shifts. An "off" icon that simply dims feels
    /// switched off and disabled; keeping the pill present makes the
    /// toggle look alive even when paused. Clicks are handled by
    /// GestureHandler's global dispatch using the wing geometry.
    private func toggleIcon(isOn: Bool, icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(width: 28, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.22))
            )
    }
}
