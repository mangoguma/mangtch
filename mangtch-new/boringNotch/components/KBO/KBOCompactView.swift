import SwiftUI

/// Left-wing compact view for the KBO widget. Renders the live score by
/// default; on hover it swaps to two toggle buttons (ticker on/off, TTS
/// on/off). Clicks themselves are dispatched by GestureHandler — this
/// view is purely visual since SwiftUI gesture recognisers don't fire
/// inside our .nonactivatingPanel.
struct KBOCompactView: View {
    let viewModel: KBOViewModel
    @EnvironmentObject private var notchVM: BoringViewModel

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
            .padding(.horizontal, KBOLayoutTokens.compactHorizontalPadding)
            .padding(.vertical, KBOLayoutTokens.compactVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: KBOLayoutTokens.compactBackgroundCornerRadius,
                                 style: .continuous)
                    .fill(Color.accentColor.opacity(isHovering ? 0.18 : 0))
                    .padding(.horizontal, KBOLayoutTokens.compactBackgroundHorizontalInset)
                    .padding(.vertical, KBOLayoutTokens.compactBackgroundVerticalInset)
            )
            .animation(.easeInOut(duration: 0.18), value: isHovering)
            .onAppear { pulse = true }
        } else {
            Image(systemName: "baseball")
                .font(TypographyTokens.expandedCaptionLarge)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Score (default)

    private func scoreView(game: KBOGame) -> some View {
        let attacking = viewModel.currentAttackingSide
        let awayBatting = attacking == .away
        let homeBatting = attacking == .home
        return HStack(spacing: KBOLayoutTokens.compactRowSpacing) {
            VStack(alignment: .leading, spacing: KBOLayoutTokens.compactInnerVerticalSpacing) {
                HStack(spacing: KBOLayoutTokens.compactLiveBadgeSpacing) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: KBOLayoutTokens.compactLiveDotSize,
                               height: KBOLayoutTokens.compactLiveDotSize)
                        .opacity(pulse ? 0.5 : 1.0)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                   value: pulse)
                    Text("LIVE")
                        .font(TypographyTokens.microBadge)
                        .foregroundStyle(.red)
                }
                Text(game.statusInfo.isEmpty ? "—" : game.statusInfo)
                    .font(TypographyTokens.tinyLabelMedium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: KBOLayoutTokens.compactScoreSpacing) {
                teamName(game.awayTeamName, isBatting: awayBatting)
                Text("\(game.awayTeamScore)")
                    .font(TypographyTokens.kboCompactScore)
                    .monospacedDigit()
                Text(":")
                    .font(TypographyTokens.expandedSmallBold)
                    .foregroundStyle(.tertiary)
                Text("\(game.homeTeamScore)")
                    .font(TypographyTokens.kboCompactScore)
                    .monospacedDigit()
                teamName(game.homeTeamName, isBatting: homeBatting)
            }
        }
    }

    /// The batting side is signalled by underlining the team name. A
    /// colour change competed with the LIVE accent and the score numerals
    /// — the underline keeps the typographic palette quiet while still
    /// reading as a strong glance signal in the narrow wing.
    private func teamName(_ name: String, isBatting: Bool) -> some View {
        Text(name)
            .font(isBatting ? TypographyTokens.expandedSmallBold : TypographyTokens.expandedSmallMedium)
            .foregroundStyle(.secondary)
            .underline(isBatting, color: .secondary)
            .lineLimit(1)
    }

    // MARK: - Hover toggles

    private var hoverToggles: some View {
        HStack(spacing: KBOLayoutTokens.compactToggleSpacing) {
            toggleIcon(
                isOn: viewModel.tickerEnabled,
                icon: "captions.bubble.fill"
            )
            .wingHitZone(.kboTickerToggle)
            toggleIcon(
                isOn: viewModel.ttsEnabled,
                icon: "speaker.wave.2.fill"
            )
            .wingHitZone(.kboTTSToggle)
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
            .font(TypographyTokens.expandedHeader)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(width: KBOLayoutTokens.compactToggleWidth,
                   height: KBOLayoutTokens.compactToggleHeight)
            .background(
                RoundedRectangle(cornerRadius: KBOLayoutTokens.compactToggleCornerRadius,
                                 style: .continuous)
                    .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.22))
            )
    }
}
