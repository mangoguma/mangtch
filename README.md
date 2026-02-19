<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_14.0+-black?style=flat-square&logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/github/license/mangoguma/mangtch?style=flat-square" alt="License">
  <img src="https://img.shields.io/github/v/release/mangoguma/mangtch?style=flat-square&label=release" alt="Release">
</p>

<h1 align="center">mangtch</h1>

<p align="center">
  <b>Transform your MacBook notch into a productivity hub</b><br>
  MacBook 노치를 생산성 허브로 바꿔보세요
</p>

<p align="center">
  <!-- TODO: Add screenshot/GIF here -->
  <!-- <img src="assets/demo.gif" width="600" alt="mangtch demo"> -->
</p>

---

## ✨ Features

- **🎵 Music Player** — Now Playing info, playback controls, audio visualizer with real-time spectrum bars
- **📁 File Shelf** — Drag & drop files onto the notch for quick temporary storage
- **🔊 System HUD** — Custom volume, brightness, and keyboard backlight sliders replacing macOS defaults
- **⬇️ Downloads** — Track download progress right from the notch
- **⏱️ Timer** — Quick access countdown timer and stopwatch
- **🎨 Themes** — Album art-based dynamic theming, dark/light mode support
- **⌨️ Global Shortcut** — Toggle panel with `Cmd+Shift+N`
- **🪶 Lightweight** — No external dependencies, Apple frameworks only

---

## 📋 Requirements

| Requirement | Details |
|-------------|---------|
| **macOS** | 14.0 (Sonoma) or later |
| **Hardware** | MacBook with a notch (Pro 14"/16" 2021+, Air 13"/15" M2+) |
| **Chip** | Apple Silicon recommended, Intel supported (best-effort) |
| **Build** | Xcode 15.0+ or Swift 5.9+ command line tools |

> [!NOTE]
> mangtch requires a MacBook **with a notch**. External displays and non-notch MacBooks are not currently supported.

---

## 📦 Installation

### Download Release

Download the latest `.app` from the [**Releases**](https://github.com/mangoguma/mangtch/releases) page, move it to `/Applications`, and launch.

### Build with Xcode

1. Clone the repo and open `Mangtch/Package.swift` in Xcode
   ```bash
   git clone https://github.com/mangoguma/mangtch.git
   open mangtch/Mangtch/Package.swift
   ```
2. Select the **Mangtch** scheme and **My Mac** as the run destination
3. `Cmd+R` to build & run, or `Cmd+B` to build only
4. To export a `.app` bundle: **Product → Archive → Distribute App**

### Build from Source (CLI)

```bash
git clone https://github.com/mangoguma/mangtch.git
cd mangtch/Mangtch

# Build & run (debug)
swift build
.build/arm64-apple-macosx/debug/Mangtch

# Or build .app bundle (release)
./build-app.sh
open .build/release/Mangtch.app

# Install to Applications
cp -r .build/release/Mangtch.app /Applications/
```

---

## 🏗️ Architecture

```
Mangtch/
├── Sources/
│   ├── App/                    # Entry point, AppDelegate, MenuBar
│   ├── Core/
│   │   ├── NotchWindow/        # NSPanel-based notch overlay
│   │   ├── Animation/          # Spring animation tokens
│   │   ├── EventBus/           # Combine-based event system
│   │   ├── Gesture/            # Hover, click, HUD suppression
│   │   ├── Settings/           # UserDefaults, global shortcuts
│   │   └── Theme/              # Theme engine, color extraction
│   ├── Widgets/
│   │   ├── MusicPlayer/        # Now Playing, controls, visualizer
│   │   ├── FileShelf/          # Drag & drop file storage
│   │   ├── HUD/                # Volume/brightness custom HUD
│   │   ├── Download/           # Download progress tracking
│   │   └── Timer/              # Countdown & stopwatch
│   ├── SystemBridge/           # MediaRemote (private API), IOKit
│   └── Settings/               # Settings UI views
├── Tests/                      # Unit tests
├── Package.swift               # SPM manifest
└── build-app.sh                # .app bundle build script
```

### State Machine

```
idle ──(hover)──▶ hovering ──(click)──▶ expanded
  ▲                  │                      │
  └──────────────────┘                      │
         (mouse leave)    (click outside/ESC)│
  ▲                                         │
  └─────────────────────────────────────────┘
```

### Widget System

All widgets implement the `NotchWidget` protocol for a plug-and-play architecture:

```swift
protocol NotchWidget: AnyObject, Identifiable {
    var id: String { get }
    var displayName: String { get }
    var icon: String { get }
    var isEnabled: Bool { get set }

    @MainActor func makeCompactView() -> AnyView   // Hover state
    @MainActor func makeExpandedView() -> AnyView   // Expanded state

    func activate()
    func deactivate()
}
```

---

## 🧪 Testing

```bash
cd Mangtch

# Run all tests
swift test

# Verify notch detection
swift test-notch.swift
```

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repo and create a feature branch
2. Follow Swift API Design Guidelines
3. Include unit tests for new features
4. Use descriptive commit messages: `[Module] Description`

```
[MediaBridge] Fix Spotify now playing detection
[NotchWindow] Add multi-monitor support
[UI] Improve animation smoothness
```

---

## ⚠️ Known Issues

- **Spotify integration** may not report now-playing info on some macOS versions
- **System HUD suppression** is not yet implemented (native OSD still appears)
- External monitor fallback mode is planned but not available yet

See the full list in [Issues](https://github.com/mangoguma/mangtch/issues).

---

## 📄 License

[MIT License](LICENSE) — free to use, modify, and distribute.

---

## 🙏 Acknowledgments

Inspired by [boring.notch](https://github.com/TheBoredTeam/boring.notch) and the macOS notch app ecosystem.

Built with ❤️ by [mangoguma](https://github.com/mangoguma)
