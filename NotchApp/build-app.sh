#!/bin/bash
set -e

echo "Building NotchApp..."

# Build the executable with Swift PM
swift build -c release

# Create app bundle structure
APP_NAME="NotchApp.app"
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
cp .build/release/NotchApp "$MACOS_DIR/NotchApp"

# Copy Info.plist
cp Info.plist "$CONTENTS_DIR/Info.plist"

# Update Info.plist bundle identifier
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable NotchApp" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.notchapp.NotchApp" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName NotchApp" "$CONTENTS_DIR/Info.plist"

# Make executable
chmod +x "$MACOS_DIR/NotchApp"

echo "✓ App bundle created at $APP_DIR"
echo ""
echo "To run: open $APP_DIR"
echo "To install: cp -r $APP_DIR /Applications/"
