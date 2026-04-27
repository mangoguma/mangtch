#!/bin/bash
set -e

echo "Building Mangtch..."

# Build the executable with Swift PM
swift build -c release

# Create app bundle structure
APP_NAME="Mangtch.app"
APP_DIR=".build/release/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating app bundle at $APP_DIR..."

# Clean previous build
rm -rf "$APP_DIR"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp .build/release/Mangtch "$MACOS_DIR/Mangtch"

# Copy Info.plist
cp Info.plist "$CONTENTS_DIR/Info.plist"

# Copy app icon if available
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo "✓ App icon bundled"
fi

# Copy Sparkle framework
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d | head -1)
if [ -n "$SPARKLE_FRAMEWORK" ]; then
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
    echo "✓ Sparkle.framework bundled"
else
    echo "⚠ Sparkle.framework not found in .build — update checking may not work"
fi

# Update Info.plist bundle identifier
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Mangtch" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.yojeong.mangtch" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Mangtch" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :NSMainStoryboardFile" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :NSPrincipalClass" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true

# Fix rpath so Sparkle.framework is found at runtime
install_name_tool -add_rpath @executable_path/../Frameworks "$MACOS_DIR/Mangtch" 2>/dev/null || true
echo "✓ rpath set for Frameworks"

# Make executable
chmod +x "$MACOS_DIR/Mangtch"

# Code signing identity selection.
# Preference order:
#   1) MANGTCH_SIGN_IDENTITY env var (CI / explicit override)
#   2) "Apple Development: …" cert from Xcode (free Apple ID; passes TCC trust)
#   3) Self-signed "Mangtch Code Signing" (codesign-valid but TCC silently denies)
#   4) Ad-hoc "-" (cdhash changes every build, TCC permissions reset)
# Apple Development is the sweet spot: stable cdhash + macOS-trusted chain so
# TCC dialogs actually appear and permissions persist across rebuilds.
SIGN_IDENTITY="${MANGTCH_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
        | awk -F'"' '/Apple Development:/ {print $2; exit}')
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
        | awk -F'"' '/Mangtch Code Signing/ {print $2; exit}')
fi

if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" \
        && echo "✓ Code signed with '$SIGN_IDENTITY'" \
        || echo "⚠ Code signing with '$SIGN_IDENTITY' failed"
else
    codesign --force --deep --sign - "$APP_DIR" 2>/dev/null \
        && echo "✓ Code signed (ad-hoc; TCC permissions reset on each rebuild)" \
        || echo "⚠ Code signing failed"
fi

echo "✓ App bundle created at $APP_DIR"
echo ""
echo "To run: open $APP_DIR"
echo "To install: cp -r $APP_DIR /Applications/"
