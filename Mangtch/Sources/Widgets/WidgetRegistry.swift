import SwiftUI
import Combine

@Observable
@MainActor
final class WidgetRegistry {
    static let shared = WidgetRegistry()

    // MARK: - State

    private(set) var widgets: [AnyNotchWidget] = []

    var enabledWidgets: [AnyNotchWidget] {
        widgets.filter { $0.isEnabled }
    }

    // MARK: - Init

    private init() {}

    // MARK: - Registration

    func registerDefaults() {
        register(MusicPlayerWidget())
        register(FileShelfWidget())
        register(TimerWidget())
        register(KBOWidget())
    }

    func register(_ widget: some NotchWidget) {
        guard !widgets.contains(where: { $0.id == widget.id }) else { return }
        let wrapped = AnyNotchWidget(widget)
        widgets.append(wrapped)
        recomputeMaxWingWidth()
    }

    func unregister(id: String) {
        if let widget = widgets.first(where: { $0.id == id }) {
            widget.deactivate()
        }
        widgets.removeAll { $0.id == id }
        recomputeMaxWingWidth()
    }

    /// Derive `NotchViewModel.maxWingWidth` per-VM from the widest registered
    /// widget's `preferredPanelWidth`. Eliminates the magic literal that
    /// drifted every time a widget grew (KBO 540 → 820 → ...). Floor is
    /// `minWingWidth` so the existing geometry invariant `panelWidth ==
    /// notchWidth + 2·wingWidth` still holds for narrow widgets; absolute
    /// ceiling 480 prevents a runaway widget from bricking layout.
    private func recomputeMaxWingWidth() {
        let declared = widgets.compactMap { $0.preferredPanelWidth }
        let widest = max(declared.max() ?? NotchViewModel.defaultPanelWidth,
                         NotchViewModel.defaultPanelWidth)
        for vm in NotchWindowManager.shared.allViewModels {
            let derived = (widest - vm.notchGeometry.notchWidth) / 2
            vm.maxWingWidth = min(max(derived, NotchViewModel.minWingWidth), 480)
            vm.updatePanelDimensions()
        }
    }

    // MARK: - Queries

    func widget(for id: String) -> AnyNotchWidget? {
        widgets.first { $0.id == id }
    }

    func widgets(for position: WidgetPosition) -> [AnyNotchWidget] {
        enabledWidgets.filter { $0.preferredPosition == position }
    }

    // MARK: - Lifecycle

    func activateAll() {
        for widget in enabledWidgets {
            widget.activate()
        }
    }

    func deactivateAll() {
        for widget in widgets {
            widget.deactivate()
        }
    }

    func enable(id: String) {
        if let widget = widgets.first(where: { $0.id == id }) {
            widget.isEnabled = true
            widget.activate()
        }
    }

    func disable(id: String) {
        if let widget = widgets.first(where: { $0.id == id }) {
            widget.isEnabled = false
            widget.deactivate()
        }
    }
}
