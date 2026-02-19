import SwiftUI
import AppKit

/// Multi-page onboarding view that guides users through initial setup.
struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var accessibilityGranted = AXIsProcessTrusted()
    var onComplete: () -> Void

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let totalPages = 3

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                welcomePage
                    .tag(0)
                accessibilityPage
                    .tag(1)
                completionPage
                    .tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation { currentPage -= 1 }
                    }
                }

                Spacer()

                // Page indicator
                HStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if currentPage < totalPages - 1 {
                    Button("Continue") {
                        withAnimation { currentPage += 1 }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") {
                        SettingsManager.shared.hasCompletedOnboarding = true
                        onComplete()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 440)
        .onReceive(permissionTimer) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to Mangtch")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Transform your MacBook's notch into a powerful\ncontrol center for music, files, and system info.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(30)
    }

    // MARK: - Page 2: Accessibility Permission

    private var accessibilityPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(accessibilityGranted ? .green : .orange)

            Text("Accessibility Permission")
                .font(.title)
                .fontWeight(.semibold)

            Text("Mangtch needs Accessibility permission to replace\nthe system volume & brightness HUD with its own.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Status indicator
            HStack(spacing: 8) {
                Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(accessibilityGranted ? .green : .red)
                    .font(.title3)
                Text(accessibilityGranted ? "Permission Granted" : "Permission Not Granted")
                    .font(.headline)
                    .foregroundStyle(accessibilityGranted ? .green : .primary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(accessibilityGranted ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            )

            if !accessibilityGranted {
                Button(action: openAccessibilitySettings) {
                    Label("Open System Settings", systemImage: "gear")
                        .frame(minWidth: 200)
                }
                .controlSize(.large)

                Text("After granting permission, this page will update automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(30)
    }

    // MARK: - Page 3: Completion

    private var completionPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Mangtch is ready to use.\nHover over your notch to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "music.note", title: "Music Control", description: "Control Spotify & Apple Music")
                featureRow(icon: "doc.on.doc", title: "File Shelf", description: "Quick access to recent files")
                featureRow(icon: "speaker.wave.2", title: "System HUD", description: "Beautiful volume & brightness overlay")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.5))
            )

            Spacer()
        }
        .padding(30)
    }

    // MARK: - Helpers

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
