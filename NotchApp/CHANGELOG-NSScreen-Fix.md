# NSScreen.main Fix - Changelog

## Problem

When running Mangtch via `swift run`, `NSScreen.main` returned `nil` or the wrong screen, causing:
- "No main screen found" errors
- `safeAreaInsets.top = 0.0` instead of the expected `38.0` on Macs with a notch
- App failing to position itself correctly

## Root Causes

1. **Timing Issue**: `NSScreen.main` can be `nil` before `NSApplication` connects to WindowServer
2. **Multi-Monitor Issue**: `NSScreen.main` returns the screen with keyboard focus, not necessarily the built-in display with the notch

## Solution

### 1. Added NSApplication Activation (AppDelegate.swift)

```swift
// Ensure app is activated and connected to WindowServer
NSApplication.shared.activate(ignoringOtherApps: true)
```

### 2. Delayed Window Setup (AppDelegate.swift)

```swift
// Setup notch window with delay to ensure WindowServer connection
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    Task { @MainActor in
        NotchWindow.shared.setup()
    }
}
```

### 3. Changed Screen Detection (NotchShape.swift, NotchWindow.swift)

**Before:**
```swift
guard let screen = NSScreen.main else { ... }
```

**After:**
```swift
// Use screens[0] (built-in display) instead of .main
// because .main returns the screen with focus, which might be external
guard let screen = NSScreen.screens.first else { ... }
```

### 4. Added Retry Logic (NotchWindow.swift)

If screen is not available on first attempt, retry after 0.5 seconds.

## Results

The app now successfully:
- Detects `NSScreen.screens[0]` (built-in display)
- Reads `safeAreaInsets.top = 38.0` correctly
- Positions window at `(600.0, 851.0, 600.0, 318.0)`
- Shows "✓ Notch detected! notchHeight=38.0, hasNotch=true"

## Files Modified

1. `/Sources/App/AppDelegate.swift`
   - Added NSApplication activation
   - Added delay before window setup
   - Added logging

2. `/Sources/Core/NotchWindow/NotchWindow.swift`
   - Changed `NSScreen.main` → `NSScreen.screens.first`
   - Added retry logic with logging
   - Updated both `setup()` and `reposition()` methods

3. `/Sources/Core/NotchWindow/NotchShape.swift`
   - Changed `NSScreen.main` → `NSScreen.screens.first` in `detect()`
   - Added comment explaining the change

## New Files Created

1. `Info.plist` - Bundle configuration for .app
2. `build-app.sh` - Script to build proper .app bundle
3. `test-notch.swift` - Diagnostic script for testing screen detection
4. `BUILD.md` - Build and installation instructions

## Testing

```bash
# Build
swift build

# Run and verify
.build/arm64-apple-macosx/debug/Mangtch

# Expected output:
[Mangtch] applicationDidFinishLaunching started
[Mangtch] NSApplication activated
[NotchWindow] ✓ Built-in screen found (screens[0])
[NotchWindow] ✓ Notch detected! notchHeight=38.0, hasNotch=true
[NotchWindow] Panel frame set: (600.0, 851.0, 600.0, 318.0)
[NotchWindow] ✓ Window setup complete and visible
```

## Future Considerations

- Consider adding support for non-notch Macs (fallback mode)
- Add preference for which screen to use in multi-monitor setups
- Add accessibility permission requests if needed
