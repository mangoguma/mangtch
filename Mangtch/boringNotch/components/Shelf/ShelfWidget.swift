import SwiftUI

/// Panel-only widget hosting the upstream boring.notch file shelf.
///
/// The shelf never claims the wings: it has no foreground activity of its
/// own, so `wingPriority` is the reserved 0 and `claimsWings` is false.
/// Drag-to-notch selects it as the expanded widget (see
/// `AppDelegate.handleDragEntersNotchRegion` and `ContentView`).
@MainActor
final class ShelfWidget: NotchWidget {
    static let widgetID = "shelf"

    let id = ShelfWidget.widgetID
    let displayName = "Shelf"
    let icon = "tray.fill"
    var isEnabled: Bool = true

    let wingPriority: Int = 0

    @MainActor
    var claimsWings: Bool { false }

    /// Wide enough for the share tile plus a few items without truncating
    /// item labels; capped at the shared panel ceiling.
    var widthRange: WidthRange {
        WidthRange(min: ShelfLayoutTokens.panelMinWidth,
                   ideal: ShelfLayoutTokens.panelIdealWidth,
                   max: LayoutTokens.panelMaxWidth)
    }

    var heightRange: HeightRange {
        .fixed(ShelfLayoutTokens.expandedHeight)
    }

    @MainActor
    func makeLeftWingView() -> AnyView {
        AnyView(ShelfLeftWing())
    }

    @MainActor
    func makeRightWingView() -> AnyView {
        AnyView(ShelfRightWing())
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        // ShelfView's dashed drop panel is a Shape with no intrinsic height,
        // so the expanded-height measurement needs an explicit frame here.
        AnyView(
            ShelfView()
                .frame(height: ShelfLayoutTokens.expandedHeight)
        )
    }

    func activate() {}
    func deactivate() {}
}

enum ShelfLayoutTokens {
    static let panelMinWidth: CGFloat = 480
    static let panelIdealWidth: CGFloat = 560
    /// Share tile (square) + one row of 56pt thumbnails with 2-line labels,
    /// plus the dashed panel's inner padding.
    static let expandedHeight: CGFloat = 150
    static let compactHorizontalPadding: CGFloat = 10
    static let compactVerticalPadding: CGFloat = 6
}

// MARK: - Wings (built for symmetry, never shown: claimsWings is false)

struct ShelfLeftWing: View {
    var body: some View {
        Image(systemName: "tray.fill")
            .font(TypographyTokens.compactGlyph)
            .foregroundStyle(ThemeTokens.textSecondary)
            .padding(.horizontal, ShelfLayoutTokens.compactHorizontalPadding)
            .padding(.vertical, ShelfLayoutTokens.compactVerticalPadding)
    }
}

struct ShelfRightWing: View {
    @ObservedObject private var shelf = ShelfStateViewModel.shared

    var body: some View {
        Text("\(shelf.items.count)")
            .font(TypographyTokens.compactTitle)
            .monospacedDigit()
            .foregroundStyle(ThemeTokens.textPrimary)
            .padding(.horizontal, ShelfLayoutTokens.compactHorizontalPadding)
            .padding(.vertical, ShelfLayoutTokens.compactVerticalPadding)
    }
}
