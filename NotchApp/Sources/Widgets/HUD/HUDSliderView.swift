import SwiftUI

struct HUDSliderView: View {
    let type: HUDType
    let value: Float
    let iconName: String
    @ObservedObject private var themeEngine = ThemeEngine.shared

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(themeEngine.currentTheme.hudIconColor)
                .frame(width: 22)

            // Slider track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(themeEngine.currentTheme.hudSliderTrackColor)
                        .frame(height: 6)

                    // Fill
                    Capsule()
                        .fill(themeEngine.currentTheme.hudSliderFillColor)
                        .frame(width: max(0, geo.size.width * CGFloat(value)), height: 6)
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: value)
                }
            }
            .frame(height: 6)

            // Percentage
            Text("\(Int(value * 100))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(themeEngine.currentTheme.textSecondary)
                .frame(width: 28, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeEngine.currentTheme.panelMaterial)
        )
    }
}
