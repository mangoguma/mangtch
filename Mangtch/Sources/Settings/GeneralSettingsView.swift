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

                Toggle("Hide in fullscreen", isOn: Binding(
                    get: { settings.hideInFullscreen },
                    set: { settings.hideInFullscreen = $0 }
                ))
                Text("Automatically hide the notch panel when a fullscreen app is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { settings.automaticallyCheckForUpdates },
                    set: { settings.automaticallyCheckForUpdates = $0 }
                ))

                HStack {
                    Text("Current version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                        .foregroundStyle(.secondary)
                }

                Button("Check for Updates Now…") {
                    UpdateManager.shared.checkForUpdates()
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
