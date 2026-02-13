import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))

                Toggle("Show in menu bar", isOn: Binding(
                    get: { settings.showInMenuBar },
                    set: { settings.showInMenuBar = $0 }
                ))
            }

            Section("Behavior") {
                Toggle("Enable animations", isOn: Binding(
                    get: { settings.animationsEnabled },
                    set: { settings.animationsEnabled = $0 }
                ))

                HStack {
                    Text("Hover sensitivity")
                    Slider(
                        value: Binding(
                            get: { settings.hoverSensitivity },
                            set: { settings.hoverSensitivity = $0 }
                        ),
                        in: 0...1,
                        step: 0.1
                    )
                }
            }

            Section("HUD") {
                Toggle("Replace system HUD", isOn: Binding(
                    get: { settings.suppressSystemHUD },
                    set: { settings.suppressSystemHUD = $0 }
                ))

                HStack {
                    Text("Auto-hide delay")
                    Slider(
                        value: Binding(
                            get: { settings.hudAutoHideDelay },
                            set: { settings.hudAutoHideDelay = $0 }
                        ),
                        in: 1...5,
                        step: 0.5
                    )
                    Text("\(settings.hudAutoHideDelay, specifier: "%.1f")s")
                        .monospacedDigit()
                        .frame(width: 35)
                }
            }

            Section("Shortcuts") {
                HStack {
                    Text("Toggle notch panel")
                    Spacer()
                    Text(ShortcutManager.shared.currentShortcut.displayString)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
