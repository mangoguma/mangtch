import SwiftUI

// MARK: - Widget Position

enum WidgetPosition: String, CaseIterable, Codable {
    case leftWing
    case rightWing
    case center
}

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

protocol NotchWidget: AnyObject, Identifiable where ID == String {
    /// Unique identifier for this widget
    var id: String { get }

    /// Human-readable display name
    var displayName: String { get }

    /// SF Symbol icon name
    var icon: String { get }

    /// Whether the widget is currently enabled
    var isEnabled: Bool { get set }

    /// Preferred position in the notch layout
    var preferredPosition: WidgetPosition { get }

    /// Closed-state width range. `.open` is canvas-fixed and ignores this.
    @MainActor
    var widthRange: WidthRange { get }

    /// Closed-state height range.
    @MainActor
    var heightRange: HeightRange { get }

    /// Compact view for the left wing — `nil` means this widget never
    /// claims that wing. Built once per app lifetime by `AnyNotchWidget`
    /// and stable-mounted by the wing host; ContentView toggles opacity
    /// to swap owners instead of remounting, which preserves SwiftUI view
    /// identity across owner changes (no AnyView diff churn, no internal
    /// state reset, deterministic hit-zone preference emission).
    @MainActor
    func makeLeftWingView() -> AnyView?

    /// Compact view for the right wing — see `makeLeftWingView`.
    @MainActor
    func makeRightWingView() -> AnyView?

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
    let preferredPosition: WidgetPosition

    @Published var isEnabled: Bool {
        didSet { wrapped.isEnabled = isEnabled }
    }

    let wrapped: any NotchWidget

    /// Built once at registration so the wing host can stable-mount it
    /// for the life of the app. SwiftUI keeps the underlying view identity
    /// across owner toggles, so each wing's internal state (hover flags,
    /// observed-object subscriptions, animation phases) survives swaps —
    /// the only thing that changes is opacity + hit-zone emission gating.
    let leftWingView: AnyView?
    let rightWingView: AnyView?

    private let _makeExpandedView: @MainActor () -> AnyView
    private let _activate: () -> Void
    private let _deactivate: () -> Void
    private let _widthRange: @MainActor () -> WidthRange
    private let _heightRange: @MainActor () -> HeightRange

    init(_ widget: some NotchWidget) {
        self.wrapped = widget
        self.id = widget.id
        self.displayName = widget.displayName
        self.icon = widget.icon
        self.preferredPosition = widget.preferredPosition
        self.isEnabled = widget.isEnabled
        self.leftWingView = widget.makeLeftWingView()
        self.rightWingView = widget.makeRightWingView()
        self._makeExpandedView = { widget.makeExpandedView() }
        self._activate = { widget.activate() }
        self._deactivate = { widget.deactivate() }
        self._widthRange = { widget.widthRange }
        self._heightRange = { widget.heightRange }
    }

    var widthRange: WidthRange {
        _widthRange()
    }

    var heightRange: HeightRange {
        _heightRange()
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

    /// Widgets that don't claim a wing slot return nil — the wing host
    /// won't mount any tree for them, so they cost nothing in the ZStack.
    @MainActor
    func makeLeftWingView() -> AnyView? { nil }

    @MainActor
    func makeRightWingView() -> AnyView? { nil }
}
