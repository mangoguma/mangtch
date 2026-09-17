#!/bin/bash
# Build, Developer ID sign, notarize, staple and zip a Mangtch release.
#
#   Mangtch/scripts/release.sh 0.10.6
#
# Env:
#   SIGN_ID         codesign identity (default: first "Developer ID Application" in keychain)
#   NOTARY_PROFILE  notarytool keychain profile (default: mangtch)
#   SKIP_NOTARIZE=1 sign only; for checking the signing path without a Developer ID cert
set -euo pipefail

VERSION="${1:?usage: release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NOTARY_PROFILE="${NOTARY_PROFILE:-mangtch}"
ENTITLEMENTS="$ROOT/release.entitlements"
OUT="$ROOT/build-release/Build/Products/Release"
APP="$OUT/Mangtch.app"
ZIP="$OUT/Mangtch-$VERSION.zip"

if [ -z "${SIGN_ID:-}" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"' || true)"
fi
[ -n "$SIGN_ID" ] || { echo "no Developer ID Application identity in keychain" >&2; exit 1; }
TEAM="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<<"$SIGN_ID")"
echo "signing with: $SIGN_ID"

# Built unsigned, then signed by hand inside-out: Xcode's CodeSignOnCopy doesn't
# cover the Mach-O in Resources (MediaRemoteAdapterTestClient), and notarization
# rejects any binary without Hardened Runtime + secure timestamp.
LOG="$ROOT/build-release/xcodebuild.log"
mkdir -p "$ROOT/build-release"
xcodebuild -project "$ROOT/boringNotch.xcodeproj" -scheme boringNotch \
  -configuration Release -derivedDataPath "$ROOT/build-release" \
  CODE_SIGNING_ALLOWED=NO build >"$LOG" 2>&1 \
  || { tail -30 "$LOG"; exit 1; }
grep -q "BUILD SUCCEEDED" "$LOG" || { tail -30 "$LOG"; exit 1; }

built="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$built" = "$VERSION" ] || { echo "built $built but asked for $VERSION (bump MARKETING_VERSION first)" >&2; exit 1; }

sign() { codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$@"; }

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
# Downloader.xpc ships its own entitlements; keep them.
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/Frameworks/Lottie.framework"
sign "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
sign "$APP/Contents/Resources/MediaRemoteAdapterTestClient"
sign --entitlements "$ENTITLEMENTS" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

# Every Mach-O must now carry our signature; catches binaries added later.
while IFS= read -r f; do
  file "$f" | grep -q 'Mach-O' || continue
  # Capture first: grep -q exits early and pipefail would flag codesign's SIGPIPE.
  info="$(codesign -dv "$f" 2>&1 || true)"
  [[ "$info" == *"flags="*"runtime"* && "$info" == *"TeamIdentifier=${TEAM}"* ]] \
    || { echo "unsigned, wrong team or no runtime: $f" >&2; exit 1; }
done < <(find "$APP" -type f -perm +111)

if [ "${SKIP_NOTARIZE:-}" = 1 ]; then
  echo "signed (not notarized): $APP"
  exit 0
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
# Re-zip so the shipped archive contains the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP"
echo "ready: $ZIP"
