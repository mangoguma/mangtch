import AppKit
import Foundation

/// Catches the OS Apple Event that fires when something opens a `mangtch://`
/// URL (in our case the Spotify OAuth redirect) and routes it to SpotifyAuth.
///
/// LSUIElement apps don't get `application(_:open:)` automatically — we have
/// to register an NSAppleEventManager handler for the GURL/GURL event ourselves.
@MainActor
final class SpotifyURLHandler: NSObject {
    static let shared = SpotifyURLHandler()

    private override init() { super.init() }

    /// Call once during applicationDidFinishLaunching.
    func register() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString)
        else { return }

        guard url.scheme == "mangtch" else { return }

        if url.host == "spotify-callback" {
            SpotifyAuth.shared.handleCallback(url: url)
        }
    }
}
