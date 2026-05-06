import SwiftUI
import Defaults

struct WidgetSettingsView: View {
    @State private var registry = WidgetRegistry.shared
    @Default(.expandedDragDetection) private var expandedDragDetection
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.minimumHoverDuration) private var minimumHoverDuration
    @Default(.debugOverlay) private var debugOverlay

    var body: some View {
        Form {
            Section("Widgets") {
                ForEach(registry.widgets) { widget in
                    HStack {
                        Image(systemName: widget.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading) {
                            Text(widget.displayName)
                                .font(.body)

                            Text(positionLabel(widget.preferredPosition))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { widget.isEnabled },
                            set: { newValue in
                                if newValue {
                                    registry.enable(id: widget.id)
                                } else {
                                    registry.disable(id: widget.id)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Notch") {
                Toggle(isOn: $openNotchOnHover) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open on hover")
                        Text("Dwell over the notch to expand. Disable to require a swipe-down or click.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Hover duration")
                    Spacer()
                    Picker("", selection: $minimumHoverDuration) {
                        Text("Instant").tag(0.0)
                        Text("0.2s").tag(0.2)
                        Text("0.3s").tag(0.3)
                        Text("0.5s").tag(0.5)
                        Text("1s").tag(1.0)
                    }
                    .frame(width: 100)
                    .disabled(!openNotchOnHover)
                }

                Toggle(isOn: $debugOverlay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Debug overlay")
                        Text("Show hover zones and timer on the notch panel.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("File Shelf") {
                @State var settings = SettingsManager.shared

                Toggle(isOn: $expandedDragDetection) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-expand on drag")
                        Text("Open the shelf when a file is dragged toward the notch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: expandedDragDetection) { _, newValue in
                    if newValue {
                        DragDetector.shared.start()
                    } else {
                        DragDetector.shared.stop()
                    }
                }

                HStack {
                    Text("Maximum files")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.fileShelfMaxItems },
                        set: { settings.fileShelfMaxItems = $0 }
                    )) {
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("20").tag(20)
                    }
                    .frame(width: 80)
                }

                HStack {
                    Text("Auto-expire after")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.fileShelfExpirationHours },
                        set: { settings.fileShelfExpirationHours = $0 }
                    )) {
                        Text("1 hour").tag(1)
                        Text("6 hours").tag(6)
                        Text("12 hours").tag(12)
                        Text("24 hours").tag(24)
                        Text("Never").tag(0)
                    }
                    .frame(width: 120)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func positionLabel(_ position: WidgetPosition) -> String {
        switch position {
        case .leftWing: return "Left wing"
        case .rightWing: return "Right wing"
        case .center: return "Center panel"
        }
    }
}
