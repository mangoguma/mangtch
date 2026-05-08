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
- **🎤 Synced Lyrics** — Time-synced lyrics fetched from LRCLIB scroll inline with the track. Falls back to plain lyrics, or hides cleanly when none exist.
- **📁 File Shelf** — Drag any file from Finder toward the notch and the panel auto-expands onto the shelf so you can drop it. Files stick around as a clipboard you can drag back out into other apps.
- **⏱️ Timer & Stopwatch** — Countdown timer and stopwatch with a circular progress ring; the read keeps updating in the panel.
- **⚾ KBO Schedule** — Today's Korean baseball games at a glance: live games show a pulsing badge with a live base-diamond, finished games dim the loser and tag W/L pitchers, scheduled games flank the linescore with starting pitchers (name + ERA) and first-pitch time. Pin a live game to the left wing and the score updates in place. Step day-by-day with chevrons or jump out to Naver Sports.
- **🪟 Panel-Aware Widget Switcher** — A tab row inside the expanded panel flips between widgets; the left wing follows whatever widget you're looking at while the right wing stays anchored to music. Wing previews fit content automatically.
- **🖐️ Trackpad Gestures** — Two-finger pan/scroll over the notch expands or collapses the panel. Drag a file toward the notch and the FileShelf auto-surfaces.
- **🎨 Album-Art Theming** — Dynamic colors extracted from the current track tint the panel material.
- **🖥️ Multi-Display** — Mirror the panel onto every connected display, with hover/expand state independent per screen and content (track preview, KBO box-score growth) synced across panels. External monitors fall back to a floating menu-bar pill when the hardware notch is absent.
- **⌨️ Global Shortcut** — Toggle the panel from anywhere with `Cmd+Shift+N`.
- **🪶 Apple-Frameworks Only** — No Electron, no extra runtime; just SwiftPM + Sparkle for updates.

---

## 📋 Requirements

| Requirement | Details |
|-------------|---------|
| **macOS** | 14.0 (Sonoma) or later |
| **Hardware** | Notched MacBook for the hardware-pill look; non-notched displays (older MacBooks, external monitors) get a menu-bar–height floating pill instead |
| **Chip** | Apple Silicon recommended; Intel is best-effort |
| **Build** | Xcode 15+ (for the Apple Development signing identity) or `swift` CLI 5.9+ |

---

## 📦 Installation

### Download a release

Grab the latest `.app` from the [**Releases**](https://github.com/mangoguma/mangtch/releases) page, drop it into `/Applications`, and launch.

### Build from source

```bash
git clone https://github.com/mangoguma/mangtch.git
cd mangtch/Mangtch

xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

cp -R build/Build/Products/Release/Mangtch.app /Applications/
open /Applications/Mangtch.app
```

Or open `Mangtch/boringNotch.xcodeproj` in Xcode, pick the **boringNotch** scheme + **My Mac**, and hit `Cmd+R`. The product is named **Mangtch.app**; the internal target name is still `boringNotch` (binary at `…/MacOS/boringNotch`).

> macOS TCC permissions (Apple Events for Spotify control, Accessibility for fullscreen detection) are bound to the binary's cdhash. Re-signing with the same identity preserves them; ad-hoc rebuilds invalidate them and require re-granting.

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

Mangtch is a fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch) with the upstream chrome (NSPanel host, multi-display window manager, settings shell, media controllers, Sparkle wiring) kept intact, and Mangtch's own widget contract grafted on top.

```
Mangtch/
├── boringNotch.xcodeproj/                 # single scheme: boringNotch
└── boringNotch/
    ├── boringNotchApp.swift               # @main + AppDelegate (upstream)
    ├── BoringViewCoordinator.swift        # global nav (upstream)
    ├── ContentView.swift                  # wings + WidgetSwitcherBar (rewritten for Mangtch)
    ├── Widgets/
    │   ├── NotchWidget.swift              # widget protocol — read this first
    │   └── WidgetRegistry.swift           # @Observable singleton
    ├── components/
    │   ├── Music/                         # MusicPlayerWidget + upstream player chrome
    │   ├── KBO/                           # KBO schedule / live scoreboard widget
    │   ├── Timer/                         # Countdown + stopwatch widget
    │   ├── Shelf/                         # FileShelf (upstream, kept)
    │   ├── Tabs/WidgetSwitcherBar.swift   # in-panel widget picker
    │   └── Notch/                         # NSPanel, wing hit zones, panel shape
    ├── sizing/
    │   ├── PanelLayoutMetrics.swift       # pure resolver: (widget, state) → wingWidth/panelWidth/expandedHeight
    │   ├── ThemeTokens.swift              # chrome colors (light/dark)
    │   ├── TypographyTokens.swift         # ~25 semantic fonts
    │   └── LayoutTokens.swift             # shared layout constants
    ├── observers/GestureHandler.swift     # global NSEvent monitor for hover + wing clicks
    ├── managers/                          # MusicManager, ImageService, NotchSpaceManager, …
    ├── MediaControllers/                  # NowPlaying / Apple Music / Spotify / YT Music
    └── docs/ADDING_A_WIDGET.md            # contributor guide for new widgets
```

### Widget contract

All widgets conform to `NotchWidget` (see `boringNotch/Widgets/NotchWidget.swift`):

- `widthRange` / `heightRange` — content-driven sizing. The chrome resolves layout via `PanelLayoutMetrics.resolve(widget:notchSize:state:)`. There is no measurement pass for width and no static clamp constant; widgets are the source of truth for their own size.
- `wingPriority` + `claimsWings` — state-driven priority chain decides which widget owns the wings (Timer running > KBO live > Music as floor).
- `makeLeftWingView()` / `makeRightWingView()` / `makeExpandedView()` — both wings are mandatory. Wing trees are stable-mounted; owner swaps are opacity toggles, not remounts.

Adding a new widget is a 5-step recipe in [`Mangtch/docs/ADDING_A_WIDGET.md`](Mangtch/docs/ADDING_A_WIDGET.md). `TimerWidget` is the smallest reference.

---

## 🧭 Project philosophy

Internalize these before sending a PR; reviewers will reject changes that violate them.

### 1. boring.notch is the architectural base

Upstream chrome is kept verbatim wherever possible: `boringNotchApp.swift`, `AppDelegate`, `BoringViewCoordinator`, per-screen `BoringViewModel`, `BoringNotchWindow`, multi-display window logic, `MediaControllerProtocol` + the four media controllers, Sparkle, `Defaults`, settings shell. Don't rename their types or move their files.

Mangtch contributes feature code, not framework rewrites. The whitelisted additions are:

- The widget contract (`Widgets/NotchWidget.swift`, `Widgets/WidgetRegistry.swift`)
- The wing hit-zone system (`components/Notch/{WingHitZone,FirstMouseHostingView,WingShapes}.swift`)
- The widget switcher (`components/Tabs/WidgetSwitcherBar.swift`)
- The per-widget directories (`components/{Music,KBO,Timer}/`)
- The pure layout resolver (`sizing/PanelLayoutMetrics.swift`) and the design-token files
- `observers/GestureHandler.swift`

When in doubt about scope, the rule is: extend `BoringViewModel` in place rather than introducing a new view model, and keep new widgets self-contained under `components/<Widget>/`.

### 2. No fallback shims

If something is referenced by removed code, remove the call site rather than stubbing the dependency. PR descriptions that say "I added a no-op so the build compiles" will get pushed back.

### 3. Sizing is content-driven, never measured for width

`PanelLayoutMetrics` is a pure function. Wings and the expanded panel size off the active widget's `widthRange`. The expanded panel's *height* is GeometryReader-measured (intrinsic, not flex-frame), so:

- **Never** wrap an expanded view body in `.frame(maxHeight:)` — flex-frames absorb the parent's proposal and the panel locks at a pessimistic budget instead of the real intrinsic. Use `.frame(minHeight:)` if you need a visual floor.
- **Never** introduce `Color.clear` cells without an explicit `.frame(height: …)` — they're height-greedy and silently bloat row heights.

### 4. Frontend policy — design tokens, not magic numbers

All visual values in widget code go through tokens. No exceptions in new code:

| Use case | Token source |
|---|---|
| Chrome color | `sizing/ThemeTokens.swift` |
| Widget-specific color | `components/<Widget>/<Widget>ThemeTokens.swift` |
| Font (any) | `sizing/TypographyTokens.swift` (~25 semantic fonts) |
| Spacing / sizing | `<Widget>LayoutTokens` (or `LayoutTokens` for chrome) |

**Disallowed in new code:** `Color.white`, `Color(white: 0.X)`, `Color(red:green:blue:)` literals inline, `.foregroundStyle(.secondary.opacity(N))`, `.font(.system(size: N))`, hardcoded `.padding(N)` for chrome-related spacing. Add the value to the relevant tokens file first, then reference the token.

Boring.notch upstream files (`NotchHomeView`, `MusicPlayerView`, `MusicControlsView`, `MusicVisualizer`, `AnimatedFace`, `Button+Bouncing`, anything under `Settings/`/`Shelf/`) are off-limits for token migration — leave them alone.

### 5. Animation lockstep

State-driven reflows in expanded views use `.easeInOut(duration: 0.22)`. The NSPanel resize uses bezier `(0.42, 0, 0.58, 1.0)`, which matches SwiftUI `easeInOut` exactly — so wings, panel chrome, and content all ease in lockstep. Don't introduce a new animation curve without a reason that's stronger than aesthetics.

### 6. Truncation is forbidden

`lineLimit` / `truncationMode` are banned in widget content. Grow the chrome (via `widthRange`) until the content fits. The whole point of the panel is glanceability; ellipsis defeats it.

---

## 🤝 Contributing

1. Fork, branch off `main` (`feature/<short-name>` or `fix/<short-name>`).
2. Read the [philosophy](#-project-philosophy) above; if your change touches widgets, also read [`Mangtch/docs/ADDING_A_WIDGET.md`](Mangtch/docs/ADDING_A_WIDGET.md).
3. Build + run locally (the `xcodebuild` one-liner under [Installation](#-installation)). UI work needs a screenshot or screen recording in the PR description.
4. Conventional-Commits-style messages — `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`. Korean commit messages are accepted; mixed Korean/English in body is fine. The body should answer *why*, not restate the diff.

```
feat: sync the heart button with Spotify Liked Songs via Web API
fix: keep KBO pre-game pin through schedule poll
refactor: drop greedy maxHeight on KBO gamesList
```

For sizable changes (new widget, panel-state machine touches, multi-display behavior) open an issue first so we can agree on scope before you write code.

---

## ⚠️ Known limitations

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
