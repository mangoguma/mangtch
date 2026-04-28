<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_14.0+-black?style=flat-square&logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/github/license/mangoguma/mangtch?style=flat-square" alt="License">
  <img src="https://img.shields.io/github/v/release/mangoguma/mangtch?style=flat-square&label=release" alt="Release">
</p>

<h1 align="center">mangtch</h1>

<p align="center">
  <b>Turn your MacBook notch into a glanceable control surface</b><br>
  MacBook 노치를 한눈에 보이는 컨트롤 패널로
</p>

<p align="center">
  <!-- TODO: Add screenshot/GIF here -->
  <!-- <img src="assets/demo.gif" width="600" alt="mangtch demo"> -->
</p>

---

## ✨ Features

- **🎵 Music Player** — Now-Playing info from Spotify or Apple Music, hover-to-show transport controls, album-art-driven theme tinting. Optional Spotify Web API sign-in syncs the heart button with your Liked Songs.
- **📁 File Shelf** — Drag any file from Finder toward the notch and the panel auto-expands onto the shelf so you can drop it. Files stick around as a clipboard you can drag back out into other apps.
- **⏱️ Timer & Stopwatch** — Countdown timer and stopwatch with a circular progress ring; the inning-style read continues to update in the panel.
- **⚾ KBO Schedule** — Today's Korean baseball games at a glance: live games show a pulsing badge, finished games dim the loser, scheduled games show first-pitch time. Pin a live game to the left wing and the score updates in place. Step day-by-day with chevrons or jump out to Naver Sports.
- **🪟 Widget Switcher** — A tab row inside the expanded panel flips between widgets, and the left wing follows whatever widget you're looking at while the right wing stays anchored to music.
- **🎨 Album-Art Theming** — Dynamic colors extracted from the current track tint the panel material.
- **⌨️ Global Shortcut** — Toggle the panel from anywhere with `Cmd+Shift+N`.
- **🪶 Apple-Frameworks Only** — No Electron, no extra runtime; just SwiftPM + Sparkle for updates.

---

## 📋 Requirements

| Requirement | Details |
|-------------|---------|
| **macOS** | 14.0 (Sonoma) or later |
| **Hardware** | MacBook with a notch (Pro 14"/16" 2021+, Air 13"/15" M2+) |
| **Chip** | Apple Silicon recommended; Intel is best-effort |
| **Build** | Xcode 15+ (for the Apple Development signing identity) or `swift` CLI 5.9+ |

> [!NOTE]
> mangtch needs a MacBook **with a notch**. External displays and notch-less MacBooks aren't supported yet.

---

## 📦 Installation

### Download a release

Grab the latest `.app` from the [**Releases**](https://github.com/mangoguma/mangtch/releases) page, drop it into `/Applications`, and launch.

### Build with Xcode

```bash
git clone https://github.com/mangoguma/mangtch.git
open mangtch/Mangtch/Package.swift
```

In Xcode pick the **Mangtch** scheme and **My Mac** as the destination, then `Cmd+R` to run or `Cmd+B` to build. For a distributable bundle: **Product → Archive → Distribute App**.

### Build from source (CLI)

```bash
git clone https://github.com/mangoguma/mangtch.git
cd mangtch/Mangtch

# Build the .app bundle (debug + release both work; build-app.sh assembles the bundle)
./build-app.sh

# Run it
open .build/release/Mangtch.app

# Install to /Applications
cp -R .build/release/Mangtch.app /Applications/
```

`build-app.sh` picks the most stable code-signing identity it can find:

1. `MANGTCH_SIGN_IDENTITY` env var (CI / explicit override)
2. `Apple Development: …` from your login keychain (free Apple ID via Xcode → Settings → Accounts → Manage Certificates → +)
3. A self-signed `Mangtch Code Signing` cert if you've created one
4. Ad-hoc signing as a fallback

The first three keep the cdhash stable across rebuilds, so macOS TCC permissions (Apple Events for Spotify control, Accessibility for fullscreen detection) survive every rebuild. Ad-hoc rebuilds invalidate them.

---

## 🎵 Spotify setup (optional, for the heart button)

The play / pause / skip controls work over AppleScript without any setup. Only the heart button — which mirrors your Spotify Liked Songs — needs Web API access, because Spotify's AppleScript `starred` property is a no-op.

1. Visit [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and **Create app**.
2. Name it whatever you want, set **Redirect URI** to `mangtch://spotify-callback`, and check **Web API**. Save.
3. Open the app's Basic Information page and copy the **Client ID** (you won't need the secret — mangtch uses PKCE).
4. Spotify now requires **User Management** for development-mode apps: add your own Spotify-account email under the *User Management* tab.
5. In mangtch open the menu-bar icon → **Settings…** → **General** → **Spotify**. Paste the Client ID, click **Sign in with Spotify**, allow access in the browser. Status flips to "Connected as ⟨name⟩".

The heart on the expanded player and on track-changes will now reflect the actual Liked Songs state, and tapping it adds/removes the current track via `PUT /me/library`.

---

## 🏗️ Architecture

```
Mangtch/
├── Sources/
│   ├── App/                       # AppDelegate, MangtchApp scene, menu bar, onboarding
│   ├── Core/
│   │   ├── NotchWindow/           # NSPanel host, layout, widget switcher, drag-monitor
│   │   ├── Animation/             # Spring + smooth animation tokens
│   │   ├── EventBus/              # Combine event channel
│   │   ├── Gesture/               # Hover/click handling
│   │   ├── Settings/              # SettingsManager (UserDefaults), global shortcut
│   │   └── Theme/                 # Theme engine + color extraction
│   ├── Widgets/                   # NotchWidget protocol + plug-and-play implementations
│   │   ├── MusicPlayer/           # Now-Playing, transport, visualizer, marquee
│   │   ├── FileShelf/             # Drag-and-drop file holding pen
│   │   ├── Timer/                 # Countdown + stopwatch with progress ring
│   │   └── KBO/                   # Korean baseball schedule + live scoreboard
│   ├── SystemBridge/
│   │   ├── MediaBridge.swift      # Spotify/Apple Music AppleScript polling
│   │   ├── SystemInfoBridge.swift # Battery (IOKit)
│   │   └── Spotify/               # PKCE OAuth, Web API, token Keychain store
│   └── Settings/                  # SwiftUI views for the settings window
├── Tests/                         # Unit tests
├── Package.swift                  # SwiftPM manifest (Sparkle + AppKit/IOKit/CoreAudio)
└── build-app.sh                   # Bundle assembly + code signing
```

### State machine

```
idle ──(hover)──▶ hovering ──(click)──▶ expanded
  ▲                  │                      │
  └──────────────────┴──(mouse out / ⎋ / outside-click)
```

### Widget protocol

All widgets implement `NotchWidget`. The widget switcher and the right-wing routing pick up new widgets automatically — adding a fifth widget is one `register()` call.

```swift
protocol NotchWidget: AnyObject, Identifiable where ID == String {
    var id: String { get }
    var displayName: String { get }
    var icon: String { get }                      // SF Symbol
    var isEnabled: Bool { get set }
    var preferredPosition: WidgetPosition { get }

    @MainActor func makeCompactView() -> AnyView  // Wing (~120pt wide)
    @MainActor func makeExpandedView() -> AnyView // Full panel

    func activate()
    func deactivate()
}
```

---

## 🧪 Testing

```bash
cd Mangtch

# Run unit tests
swift test

# Verify notch detection on this machine
swift test-notch.swift
```

---

## 🤝 Contributing

1. Fork and create a feature branch.
2. Follow the Swift API Design Guidelines.
3. Add unit tests for non-UI logic where it makes sense.
4. Use Conventional-Commits-style messages — the existing history follows `feat:`, `fix:`, `refactor:`, `chore:`, `polish:` prefixes:

```
feat: sync the heart button with Spotify Liked Songs via Web API
fix: open Settings via NSWindow to bypass macOS 14 SwiftUI regression
chore: remove unused Download widget
```

The body should explain *why* — what was broken or missing — not just restate the diff.

---

## ⚠️ Known limitations

- **External-display fallback** is on the roadmap; right now mangtch needs the built-in notched display.
- **KBO logos** are rendered in v1 from Naver's CDN. The endpoint is unofficial; if Naver changes the schema the widget falls back to text-only badges.
- **Spotify Web API extended access** isn't requested — the Liked Songs sync uses the unified `/me/library` endpoint and works in development mode for the registered user.

Track open issues at [Issues](https://github.com/mangoguma/mangtch/issues).

---

## 📄 License

[MIT License](LICENSE) — free to use, modify, and distribute.

---

## 🙏 Acknowledgments

Inspired by [boring.notch](https://github.com/TheBoredTeam/boring.notch) and the broader macOS notch app ecosystem.

Built with ❤️ by [mangoguma](https://github.com/mangoguma)
