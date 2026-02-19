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
        register(HUDWidget())
        register(FileShelfWidget())
        register(TimerWidget())
        register(DownloadWidget())
    }

    func register(_ widget: some NotchWidget) {
        guard !widgets.contains(where: { $0.id == widget.id }) else { return }
        let wrapped = AnyNotchWidget(widget)
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
