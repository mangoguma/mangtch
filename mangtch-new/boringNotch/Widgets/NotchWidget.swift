import SwiftUI

// MARK: - Width / Height Ranges

/// Widget-declared panel width range. `PanelLayoutMetrics.resolve` clamps
/// the active widget's `ideal` into `[min, max]` for both closed and open
/// states — there is no canvas snap.
struct WidthRange {
    let min: CGFloat        // 절대 최소 (그 이하는 콘텐츠가 깨짐)
    let ideal: CGFloat      // 기본 폭
    let max: CGFloat        // 그 이상은 chrome 낭비

    static let `default` = WidthRange(min: 320, ideal: 480, max: 640)

    /// Single-value range — `min == ideal == max`, so the metrics clamp is a
    /// no-op. Used by widgets that own a fixed pixel-design canvas (Music).
    static func fixed(_ value: CGFloat) -> WidthRange {
        WidthRange(min: value, ideal: value, max: value)
    }
}

struct HeightRange {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat

    static let `default` = HeightRange(min: 180, ideal: 260, max: 400)

    static func fixed(_ value: CGFloat) -> HeightRange {
        HeightRange(min: value, ideal: value, max: value)
    }
}

// MARK: - Widget Protocol

/// Single-owner, bilateral wings. The widget that wins the priority chain
/// (highest `wingPriority` among those whose `claimsWings` is true) owns
/// **both** wings and the expanded panel. There is no per-wing selection
/// and no user toggle — selection is purely state-driven.
///
/// Every conformer must build both wing views; one-sided wings would
/// produce an asymmetric notch chrome that no widget in the design covers.
protocol NotchWidget: AnyObject, Identifiable where ID == String {
    /// Unique identifier for this widget
    var id: String { get }

    /// Human-readable display name
    var displayName: String { get }

    /// SF Symbol icon name
    var icon: String { get }

    /// Whether the widget is currently enabled
    var isEnabled: Bool { get set }

    /// Higher value wins the priority chain. Ties are not allowed across
    /// registered widgets — `WidgetRegistry` asserts uniqueness at register
    /// time. `0` is reserved for "never claims" (no current widget uses it,
    /// but Settings-style chrome that shouldn't appear in wings would).
    var wingPriority: Int { get }

    /// State-driven claim. Read on every observation tick, so it must
    /// only depend on state already exposed via `@Observable`/`@Published`
    /// — otherwise the priority chain won't recompute when the answer
    /// changes. Returning `false` hands the wings off to the next-priority
    /// widget that returns `true`.
    @MainActor
    var claimsWings: Bool { get }

    /// Closed-state width range. `.open` is canvas-fixed and ignores this.
    @MainActor
    var widthRange: WidthRange { get }

    /// Closed-state height range.
    @MainActor
    var heightRange: HeightRange { get }

    /// Compact view for the left wing. Built once per app lifetime by
    /// `AnyNotchWidget` and stable-mounted by the wing host; ContentView
    /// toggles opacity to swap owners instead of remounting, which
    /// preserves SwiftUI view identity across owner changes (no AnyView
    /// diff churn, no internal state reset, deterministic hit-zone
    /// preference emission).
    @MainActor
    func makeLeftWingView() -> AnyView

    /// Compact view for the right wing — see `makeLeftWingView`.
    @MainActor
    func makeRightWingView() -> AnyView

    /// Expanded view shown when panel is fully expanded
    @MainActor
    func makeExpandedView() -> AnyView

    /// Called when widget becomes visible/active
    func activate()

    /// Called when widget is hidden or app is backgrounded
    func deactivate()
}

// MARK: - Type-Erased Widget Wrapper

@MainActor
final class AnyNotchWidget: Identifiable, ObservableObject {
    let id: String
    let displayName: String
    let icon: String
    let wingPriority: Int

    @Published var isEnabled: Bool {
        didSet { wrapped.isEnabled = isEnabled }
    }

    let wrapped: any NotchWidget

    /// Built once at registration so the wing host can stable-mount it
    /// for the life of the app. SwiftUI keeps the underlying view identity
    /// across owner toggles, so each wing's internal state (hover flags,
    /// observed-object subscriptions, animation phases) survives swaps —
    /// the only thing that changes is opacity + hit-zone emission gating.
    let leftWingView: AnyView
    let rightWingView: AnyView

    private let _makeExpandedView: @MainActor () -> AnyView
    private let _activate: () -> Void
    private let _deactivate: () -> Void
    private let _widthRange: @MainActor () -> WidthRange
    private let _heightRange: @MainActor () -> HeightRange
    private let _claimsWings: @MainActor () -> Bool

    init(_ widget: some NotchWidget) {
        self.wrapped = widget
        self.id = widget.id
        self.displayName = widget.displayName
        self.icon = widget.icon
        self.wingPriority = widget.wingPriority
        self.isEnabled = widget.isEnabled
        self.leftWingView = widget.makeLeftWingView()
        self.rightWingView = widget.makeRightWingView()
        self._makeExpandedView = { widget.makeExpandedView() }
        self._activate = { widget.activate() }
        self._deactivate = { widget.deactivate() }
        self._widthRange = { widget.widthRange }
        self._heightRange = { widget.heightRange }
        self._claimsWings = { widget.claimsWings }
    }

    var widthRange: WidthRange {
        _widthRange()
    }

    var heightRange: HeightRange {
        _heightRange()
    }

    var claimsWings: Bool {
        _claimsWings()
    }

    func makeExpandedView() -> AnyView {
        _makeExpandedView()
    }

    func activate() {
        _activate()
    }

    func deactivate() {
        _deactivate()
    }
}

extension NotchWidget {
    @MainActor
    var widthRange: WidthRange { .default }

    @MainActor
    var heightRange: HeightRange { .default }
}
