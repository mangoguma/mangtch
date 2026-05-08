import SwiftUI
import AppKit

/// Process-wide cache for team emblem PNGs. Logos rarely change, so once
/// fetched they live in memory for the whole session — no need for a
/// disk cache.
@MainActor
final class KBOLogoCache {
    static let shared = KBOLogoCache()
    private let store = NSCache<NSString, NSImage>()

    private init() {
        store.countLimit = 30
    }

    func image(for url: URL) async -> NSImage? {
        let key = url.absoluteString as NSString
        if let cached = store.object(forKey: key) {
            return cached
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = NSImage(data: data)
            else { return nil }
            store.setObject(image, forKey: key)
            return image
        } catch {
            return nil
        }
    }
}

/// SwiftUI wrapper that loads a team emblem URL into an NSImage, falling
/// back to a tinted text-code badge while the image is loading or if the
/// URL is missing/broken.
struct KBOTeamLogo: View {
    let url: URL?
    let teamCode: String
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            guard let url else { return }
            image = await KBOLogoCache.shared.image(for: url)
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(.tertiary.opacity(0.5))
            Text(teamCode.prefix(2))
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}
