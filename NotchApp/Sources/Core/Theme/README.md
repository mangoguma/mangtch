# Theme System

Centralized theme management for NotchApp visual tokens.

## Overview

The Theme system provides a protocol-based architecture for managing all visual design tokens including colors, materials, shadows, and geometry. This replaces hardcoded visual values throughout the codebase.

## Architecture

```
ThemeProtocol.swift      - Defines the NotchTheme protocol
ThemeEngine.swift        - Singleton manager (@MainActor, ObservableObject)
DefaultTheme.swift       - Default theme matching current design
DarkTheme.swift          - Darker color palette with deeper shadows
LightTheme.swift         - Lighter color palette with softer shadows
```

## Usage

### Accessing the current theme

```swift
import SwiftUI

struct MyView: View {
    @State private var themeEngine = ThemeEngine.shared

    var body: some View {
        VStack {
            Text("Hello")
                .foregroundColor(themeEngine.currentTheme.textPrimary)
        }
        .background(themeEngine.currentTheme.panelMaterial)
        .cornerRadius(themeEngine.currentTheme.panelCornerRadius)
    }
}
```

### Switching themes

```swift
// Switch to dark theme
ThemeEngine.shared.setTheme(DarkTheme(), name: "dark")

// Switch to light theme
ThemeEngine.shared.setTheme(LightTheme(), name: "light")

// Switch to default theme
ThemeEngine.shared.setTheme(DefaultTheme(), name: "default")
```

### Theme persistence

Theme selection is automatically persisted to UserDefaults and restored on app launch.

## Theme Tokens

### Materials & Effects
- `panelMaterial: Material` - Background material (e.g., .ultraThinMaterial)
- `shadowColor: Color` - Shadow color for panels
- `shadowRadius: CGFloat` - Shadow blur radius
- `shadowOpacity: Double` - Shadow opacity (0.0-1.0)

### Geometry
- `panelCornerRadius: CGFloat` - Corner radius for panels

### Colors
- `accentColor: Color` - Primary accent color
- `textPrimary: Color` - Primary text color
- `textSecondary: Color` - Secondary/subdued text color
- `backgroundPrimary: Color` - Primary background
- `backgroundSecondary: Color` - Secondary background for layering

### HUD-specific
- `hudSliderTrackColor: Color` - Slider track background
- `hudSliderFillColor: Color` - Slider fill color
- `hudIconColor: Color` - Icon color in HUD

## Current Values

### DefaultTheme
- Matches existing NotchApp design
- Material: `.ultraThinMaterial`
- Corner radius: `16`
- HUD slider fill: `.white`
- Sources: NotchViewModel.swift:26, NotchContentView.swift, HUDSliderView.swift

### DarkTheme
- Deeper shadows (opacity: 0.4, radius: 16)
- White text with 60% opacity for secondary
- Dark backgrounds (12-18% white)

### LightTheme
- Softer shadows (opacity: 0.12, radius: 10)
- Black text with 60% opacity for secondary
- Light backgrounds (92-96% white)

## Migration Status

**Created**: Theme infrastructure files (ThemeProtocol, ThemeEngine, DefaultTheme, DarkTheme, LightTheme)

**Not yet migrated**: Existing files still use hardcoded values. Migration will be handled separately.

## Next Steps

1. Migrate NotchContentView to use ThemeEngine
2. Migrate HUDSliderView to use ThemeEngine
3. Add theme selection UI in AppearanceSettingsView
4. Consider state-dependent shadow variations (expanded vs hovering)
