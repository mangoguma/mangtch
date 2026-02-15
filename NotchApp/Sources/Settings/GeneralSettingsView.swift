import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @State private var settings = SettingsManager.shared
    @State private var accessibilityGranted = AXIsProcessTrusted()
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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

            Section("Permissions") {
                HStack {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(accessibilityGranted ? .green : .red)
                    Text("Accessibility")
                    Spacer()
                    if accessibilityGranted {
                        Text("Granted")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Open System Settings") {
                            openAccessibilitySettings()
                        }
                    }
                }
                Text("Required for replacing the system HUD with Mangtch's HUD.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .onReceive(permissionTimer) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
