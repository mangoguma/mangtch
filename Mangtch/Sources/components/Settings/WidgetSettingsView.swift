import SwiftUI

struct WidgetSettingsView: View {
    @State private var registry = WidgetRegistry.shared

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

            Section("File Shelf") {
                @State var settings = SettingsManager.shared

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
