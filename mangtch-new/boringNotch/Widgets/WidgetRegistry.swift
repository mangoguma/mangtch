import SwiftUI
import Defaults
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
        register(TimerWidget())
        register(KBOWidget())
        applyPersistedOrder()
    }

    func register(_ widget: some NotchWidget) {
        guard !widgets.contains(where: { $0.id == widget.id }) else { return }
        let wrapped = AnyNotchWidget(widget)
        if let stored = Defaults[.widgetEnabled][wrapped.id] {
            wrapped.isEnabled = stored
        }
        widgets.append(wrapped)
    }

    func unregister(id: String) {
        if let widget = widgets.first(where: { $0.id == id }) {
            widget.deactivate()
        }
        widgets.removeAll { $0.id == id }
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

    // MARK: - User-controlled mutations

    /// Enable/disable a widget. Persists to Defaults and triggers Observation
    /// so chrome (ContentView, WidgetSwitcherBar) re-evaluates `enabledWidgets`.
    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let idx = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[idx].isEnabled = enabled
        if enabled {
            widgets[idx].activate()
        } else {
            widgets[idx].deactivate()
        }
        var dict = Defaults[.widgetEnabled]
        dict[id] = enabled
        Defaults[.widgetEnabled] = dict
        // Reassign to fire Observation on `widgets` — child @Published changes
        // alone don't propagate through the @Observable registry wrapper.
        widgets = widgets
    }

    /// Reorder via SwiftUI `.onMove` IndexSet API.
    func move(from source: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
        Defaults[.widgetOrder] = widgets.map(\.id)
    }

    // MARK: - Internal

    private func applyPersistedOrder() {
        let saved = Defaults[.widgetOrder]
        guard !saved.isEmpty else { return }
        var sorted: [AnyNotchWidget] = []
        for id in saved {
            if let w = widgets.first(where: { $0.id == id }) {
                sorted.append(w)
            }
        }
        // Append any widgets registered after the saved order was captured.
        for w in widgets where !sorted.contains(where: { $0.id == w.id }) {
            sorted.append(w)
        }
        widgets = sorted
    }
}
