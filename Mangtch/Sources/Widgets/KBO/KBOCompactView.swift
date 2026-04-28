import SwiftUI

/// Left-wing compact view for the KBO widget. Only renders meaningfully
/// when there's a selected, live game; otherwise the parent's
/// `hasContentToShow` check has already routed the slot back to music.
struct KBOCompactView: View {
    let viewModel: KBOViewModel
    @State private var pulse = false

    var body: some View {
        if let game = viewModel.selectedGame, game.isLive {
            HStack(spacing: 8) {
                // Inning + LIVE pulse on the leading edge so the user
                // immediately knows it's live without reading scores.
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

                // Score block, monospaced so digit changes don't jitter
                // the layout when scores increment.
                HStack(spacing: 3) {
                    Text(game.awayTeamCode)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(game.awayTeamScore)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(":")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text("\(game.homeTeamScore)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(game.homeTeamCode)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .onAppear { pulse = true }
        } else {
            Image(systemName: "baseball")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
