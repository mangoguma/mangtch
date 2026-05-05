import SwiftUI
import ServiceManagement
import AppKit
import Defaults

struct GeneralSettingsView: View {
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.hideInFullscreen) private var hideInFullscreen
    @Default(.animationsEnabled) private var animationsEnabled
    @Default(.showInMenuBar) private var showInMenuBar
    @Default(.showOnAllDisplays) private var showOnAllDisplays
    @Default(.notchScreen) private var notchScreen
    @Default(.automaticallyCheckForUpdates) private var automaticallyCheckForUpdates
    @Default(.spotifyClientID) private var spotifyClientID
    @ObservedObject private var spotifyAuth = SpotifyAuth.shared
    @State private var clientIDInput: String = ""
    /// Re-read on every screen-parameters change so a freshly connected
    /// or disconnected display shows up in the picker without reopening
    /// the settings window.
    @State private var availableScreens: [NSScreen] = NSScreen.screens

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)

                Toggle("Show in menu bar", isOn: $showInMenuBar)
            }

            Section("Display") {
                Toggle("Show on all displays", isOn: $showOnAllDisplays)

                if !showOnAllDisplays {
                    Picker("Show notch on", selection: $notchScreen) {
                        // Empty string = built-in (default). Use the actual
                        // screen-zero name as the label so the user can tell
                        // which physical display "Built-in" maps to.
                        let builtInLabel = NSScreen.screens.first?.localizedName ?? "Built-in"
                        Text("Built-in (\(builtInLabel))").tag("")
                        ForEach(availableScreens.dropFirst(), id: \.localizedName) { screen in
                            Text(screen.localizedName).tag(screen.localizedName)
                        }
                    }
                }
                Text("Pick which display the notch panel attaches to. " +
                     "Disconnected displays fall back to the built-in screen automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Enable animations", isOn: $animationsEnabled)

                Toggle("Hide in fullscreen", isOn: $hideInFullscreen)
                Text("Automatically hide the notch panel when a fullscreen app is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $automaticallyCheckForUpdates)

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
            clientIDInput = spotifyClientID
            availableScreens = NSScreen.screens
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            availableScreens = NSScreen.screens
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
                        .onSubmit { spotifyClientID = clientIDInput }
                    Button("Save") {
                        spotifyClientID = clientIDInput
                    }
                    .disabled(clientIDInput == spotifyClientID)
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
                        spotifyClientID = clientIDInput
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
