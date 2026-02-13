# Building NotchApp

## Quick Start

### Build and Run

```bash
# Build executable (for testing)
swift build

# Run directly
.build/arm64-apple-macosx/debug/NotchApp

# Or build release .app bundle
./build-app.sh

# Run the .app bundle
open .build/release/NotchApp.app
```

### Install

```bash
# Build and install to Applications
./build-app.sh
cp -r .build/release/NotchApp.app /Applications/
```

## Important Notes

### NSScreen.screens[0] vs NSScreen.main

The app uses `NSScreen.screens[0]` instead of `NSScreen.main` to detect the notch because:

- `NSScreen.main` returns the screen with keyboard focus, which might be an external display
- `NSScreen.screens[0]` always returns the built-in display where the notch is located
- On Macs with a notch, `screens[0].safeAreaInsets.top == 38.0`

### Running from Command Line

When running via `swift run`, the app works but you'll see the executable in the Dock briefly. For production use, build the .app bundle which runs as an accessory app (no Dock icon).

### Multi-Monitor Setup

If you have multiple monitors, the app will always position itself on the built-in display (where the notch is).

## Project Structure

- **Sources/App/** - App lifecycle (AppDelegate, NotchApp.swift)
- **Sources/Core/** - Core window management and state
- **Sources/Widgets/** - Individual widgets (Music, HUD, FileShelf)
- **Sources/SystemBridge/** - System info and media bridges
- **Info.plist** - Bundle configuration
- **build-app.sh** - Build script for creating .app bundle

## Troubleshooting

### "No notch detected"

If you see this message:
1. Make sure you're on a Mac with a notch (MacBook Pro 14" or 16" 2021+)
2. Check that the built-in display is connected and active
3. Run the test script: `./test-notch.swift` to verify screen detection

### App doesn't start

Make sure all dependencies are built:
```bash
swift build
```
