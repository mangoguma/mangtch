import SwiftUI
import AppKit

@MainActor
final class KBOWidget: NotchWidget {
    let id = "kbo"
    let displayName = "KBO"
    let icon = "baseball"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    /// Closed = 5-cell game-row layout fits in 540pt. Open = derived from
    /// the *actual* viewing linescore — innings count drives the grid
    /// width, real pitcher-name text metrics drive the starter slots.
    /// No magic literal that goes wrong on extra innings or unusually
    /// long names; the panel chrome just follows what the content needs.
    /// `viewingLinescore` is `@Observable`, NotchViewModel re-snaps
    /// wing/panel via `setupWidgetWidthObserver` whenever it flips or
    /// the inning/lineup data grows.
    var preferredPanelWidth: CGFloat? {
        guard let line = viewModel.viewingLinescore else { return 540 }
        let innings = max(line.innings, 9)
        let cellsWidth = CGFloat(innings + 4) * 22                    // grid cells
        let gridWidth = 44 + cellsWidth                                // teamCol + cells
        let leftSlot = Self.starterSlotWidth(line.awayStartingPitcher)
        let rightSlot = Self.starterSlotWidth(line.homeStartingPitcher)
        let derived = leftSlot + 8 + gridWidth + 8 + rightSlot + 16    // hstack spacing + outer pad
        return max(540, derived)
    }

    /// Width needed to render a starter slot (badge + name) without
    /// truncation. Uses real text metrics so foreign names like
    /// "로드리게스" or "에르난데스" never collide with `lineLimit(1)`.
    /// `KBOExpandedView.starterLabel` is the matching renderer.
    @MainActor
    private static func starterSlotWidth(_ name: String?) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let text = name ?? "—"
        let nameWidth = (text as NSString).size(withAttributes: [.font: font]).width
        // badge glyph (~14) + inner spacing (3) + outer slack (6).
        return ceil(nameWidth) + 14 + 3 + 6
    }

    let viewModel = KBOViewModel()

    @MainActor
    func makeCompactView() -> AnyView {
        AnyView(KBOCompactView(viewModel: viewModel))
    }

    /// Right-wing companion view: live B/S/O + bases + pitcher/batter.
    /// Mirrors MusicPlayerWidget.makeCompactInfoView(); NotchContentView
    /// uses it whenever KBO is the panel-selected widget AND a live game
    /// is pinned. Falls back to a placeholder when there's no live state.
    @MainActor
    func makeCompactInfoView() -> AnyView {
        AnyView(KBORightWingContainer(viewModel: viewModel))
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(KBOExpandedView(viewModel: viewModel))
    }

    func activate() {
        Task { @MainActor in
            viewModel.startMonitoring()
        }
    }

    func deactivate() {
        Task { @MainActor in
            viewModel.stopMonitoring()
        }
    }
}
