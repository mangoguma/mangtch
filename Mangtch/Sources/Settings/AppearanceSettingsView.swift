import SwiftUI

struct AppearanceSettingsView: View {
    @State private var settings = SettingsManager.shared
    @ObservedObject var themeEngine = ThemeEngine.shared
    @State private var selectedTheme: String = UserDefaults.standard.string(forKey: "selectedTheme") ?? "default"

    var body: some View {
        Form {
            Section("Panel") {
                HStack {
                    Text("Panel width")
                    Slider(
                        value: Binding(
                            get: { settings.panelWidthMultiplier },
                            set: { settings.panelWidthMultiplier = $0 }
                        ),
                        in: 0.8...1.5,
                        step: 0.1
                    ) {
                        Text("Width")
                    } minimumValueLabel: {
                        Text("S")
                            .font(.caption)
                    } maximumValueLabel: {
                        Text("L")
                            .font(.caption)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 20) {
                    // Theme Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Appearance")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Picker("Theme", selection: $selectedTheme) {
                            Label("Default", systemImage: "circle.lefthalf.filled")
                                .tag("default")
                            Label("Dark", systemImage: "moon.fill")
                                .tag("dark")
                            Label("Light", systemImage: "sun.max.fill")
                                .tag("light")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedTheme) { oldValue, newValue in
                            let theme = ThemeEngine.themeForName(newValue)
                            themeEngine.setTheme(theme, name: newValue)
                        }
                    }

                    Divider()

                    // Live Preview Panel
                    ThemePreviewPanel(theme: themeEngine.currentTheme)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Theme")
            } footer: {
                Text("Changes apply instantly across all app components")
                    .font(.caption)
            }

            Section {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Theme Preview Panel

struct ThemePreviewPanel: View {
    let theme: NotchTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            // Sample Notch Panel
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Sample HUD Slider
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.hudIconColor)

                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.hudSliderTrackColor)
                                .frame(height: 6)

                            // Fill
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.hudSliderFillColor)
                                .frame(width: 60, height: 6)
                        }
                        .frame(width: 100)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.panelMaterial)

                    )
                }

                // Color Swatches
                HStack(spacing: 12) {
                    ColorSwatch(color: theme.accentColor, label: "Accent")
                    ColorSwatch(color: theme.textPrimary, label: "Text")
                    ColorSwatch(color: theme.backgroundSecondary, label: "Surface")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.windowBackgroundColor).opacity(0.5))
            )
        }
    }
}

// MARK: - Color Swatch

struct ColorSwatch: View {
    let color: Color
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
