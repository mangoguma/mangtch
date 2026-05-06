import SwiftUI
import Combine

/// Centralized theme management system for Mangtch
@MainActor
final class ThemeManager: ObservableObject {
    // MARK: - Singleton

    static let shared = ThemeManager()

    // MARK: - Published State

    /// The currently active theme
    @Published private(set) var currentTheme: NotchTheme

    // MARK: - Constants

    private static let userDefaultsKey = "selectedTheme"

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var artworkSubscription: AnyCancellable?

    // MARK: - Init

    private init() {
        let savedThemeName = UserDefaults.standard.string(forKey: Self.userDefaultsKey) ?? "default"
        currentTheme = Self.themeForName(savedThemeName)

        if savedThemeName == "albumart" {
            startArtworkObservation()
        }

        // Watch for system appearance changes so "default" theme follows
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.currentThemeName == "default" else { return }
                let theme = Self.themeForName("default")
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.currentTheme = theme
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Set the active theme and persist the choice
    func setTheme(_ theme: NotchTheme, name: String) {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentTheme = theme
        }
        UserDefaults.standard.set(name, forKey: Self.userDefaultsKey)

        if name == "albumart" {
            startArtworkObservation()
        } else {
            stopArtworkObservation()
        }
    }

    /// Get a theme instance by name
    static func themeForName(_ name: String) -> NotchTheme {
        switch name.lowercased() {
        case "dark":
            return DarkTheme()
        case "light":
            return LightTheme()
        case "albumart":
            return AlbumArtTheme()
        default:
            // "default" follows macOS system appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? DarkTheme() : LightTheme()
        }
    }

    /// Get the name of the current theme
    var currentThemeName: String {
        UserDefaults.standard.string(forKey: Self.userDefaultsKey) ?? "default"
    }

    // MARK: - Album Art Observation

    private func startArtworkObservation() {
        stopArtworkObservation()

        // Apply current artwork immediately if available
        if let artwork = MusicManager.shared.currentArtwork {
            applyArtworkTheme(from: artwork)
        }

        artworkSubscription = MusicManager.shared.$currentArtwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                if let image = image {
                    self?.applyArtworkTheme(from: image)
                } else {
                    // No artwork — revert to base album art theme
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self?.currentTheme = AlbumArtTheme()
                    }
                }
            }
    }

    private func stopArtworkObservation() {
        artworkSubscription?.cancel()
        artworkSubscription = nil
    }

    private func applyArtworkTheme(from image: NSImage) {
        // Extract colors on background thread to avoid blocking UI
        Task.detached(priority: .userInitiated) {
            let palette = ColorExtractor.extract(from: image)
            let theme = AlbumArtTheme(palette: palette)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.currentTheme = theme
                }
            }
        }
    }
}
