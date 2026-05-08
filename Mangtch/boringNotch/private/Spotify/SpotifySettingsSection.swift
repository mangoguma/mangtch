import SwiftUI
import Defaults

/// Settings section for the Spotify Web API integration. Lives under the
/// Media tab. Only the heart button (Liked Songs) needs Web API auth —
/// playback (play/pause/skip) still routes through AppleScript.
struct SpotifySettingsSection: View {
    @Default(.spotifyClientID) private var spotifyClientID
    @ObservedObject private var spotifyAuth = SpotifyAuth.shared
    @State private var clientIDInput: String = ""

    var body: some View {
        Section {
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
        } header: {
            Text("Spotify")
        } footer: {
            Text("Used only to sync the heart button with your Spotify Liked Songs. " +
                 "Playback (play/pause/skip) still goes through AppleScript.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            clientIDInput = spotifyClientID
        }
    }
}
