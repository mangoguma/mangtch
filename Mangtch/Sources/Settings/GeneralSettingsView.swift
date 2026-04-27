import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @State private var settings = SettingsManager.shared
    @ObservedObject private var spotifyAuth = SpotifyAuth.shared
    @State private var clientIDInput: String = ""

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

            spotifySection
        }
        .formStyle(.grouped)
        .onAppear {
            clientIDInput = settings.spotifyClientID
        }
    }

    // MARK: - Spotify

    @ViewBuilder
    private var spotifySection: some View {
        Section("Spotify") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Client ID")
                    .font(.callout)
                HStack {
                    TextField("Paste from developer.spotify.com/dashboard", text: $clientIDInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { settings.spotifyClientID = clientIDInput }
                    Button("Save") {
                        settings.spotifyClientID = clientIDInput
                    }
                    .disabled(clientIDInput == settings.spotifyClientID)
                }
                Link("How to get a Client ID →",
                     destination: URL(string: "https://developer.spotify.com/documentation/web-api/concepts/apps")!)
                    .font(.caption)
            }

            HStack {
                Text("Status")
                Spacer()
                if spotifyAuth.isAuthorized {
                    Label(spotifyAuth.displayName.map { "Connected as \($0)" } ?? "Connected",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    Label("Not connected", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            HStack {
                if spotifyAuth.isAuthorized {
                    Button("Disconnect", role: .destructive) {
                        spotifyAuth.disconnect()
                        SpotifyAPI.shared.clearCache()
                    }
                } else {
                    Button("Sign in with Spotify") {
                        // Persist whatever the user typed before launching the browser.
                        settings.spotifyClientID = clientIDInput
                        spotifyAuth.startAuthFlow(clientID: clientIDInput)
                    }
                    .disabled(clientIDInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let error = spotifyAuth.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Used only to sync the heart button with your Spotify Liked Songs. " +
                 "Playback (play/pause/skip) still goes through AppleScript.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
