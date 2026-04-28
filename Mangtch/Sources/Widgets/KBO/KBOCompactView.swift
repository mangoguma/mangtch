import SwiftUI

/// Left-wing compact view for the KBO widget. Only renders meaningfully
/// when there's a selected, live game; otherwise the parent's
/// `hasContentToShow` check has already routed the slot back to music.
struct KBOCompactView: View {
    let viewModel: KBOViewModel

    var body: some View {
        if let game = viewModel.selectedGame, game.isLive {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(game.awayTeamCode)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(game.awayTeamScore)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("-")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("\(game.homeTeamScore)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(game.homeTeamCode)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if !game.statusInfo.isEmpty {
                    Text(game.statusInfo)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        } else {
            // Fallback icon — should rarely render thanks to hasContentToShow,
            // but covers the brief frame between selection changes.
            Image(systemName: "baseball")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
