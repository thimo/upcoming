#!/bin/bash
# Build Upcoming, wrap in a .app bundle, sign with a STABLE identity, and
# install to /Applications/Upcoming.app.
#
# /Applications, not ~/Applications: on macOS 27 the menu bar agent (and
# Bartender on top of it) only manages status items of apps running from
# /Applications. From ~/Applications the item gets parked off-screen as
# soon as Bartender runs (2026-09-26).
#
# Signing identity matters for TCC: macOS keys the Calendars grant to the
# app's designated requirement. Ad-hoc signing (`--sign -`) produces a
# fresh cdhash on every rebuild, so each rebuild would look like a brand
# new app and silently invalidate the grant (the Clawbridge lesson).
# Developer ID = stable Team ID = grant survives rebuilds.
#
# Override the identity via UPCOMING_SIGN_ID if needed.
set -euo pipefail
cd "$(dirname "$0")"

SIGN_ID="${UPCOMING_SIGN_ID:-Developer ID Application: Theodorus Jansen (SCP9WFJV88)}"

echo "==> Building release binary"
# SwiftPM 6.4's default swift-build backend hands the linker no SDK
# version, so LC_BUILD_VERSION ends up with sdk == deployment target
# (e.g. 15.0) instead of the real SDK — and macOS gates new system
# behaviour on the SDK an app was linked against. Pass it explicitly;
# ld takes this over its default (2026-09-27). Deployment target comes
# from Info.plist so there is one place to bump it (with Package.swift).
MIN_OS="$(plutil -extract LSMinimumSystemVersion raw Resources/Info.plist)"
SDK_VERSION="$(xcrun --show-sdk-version)"
swift build -c release \
  -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_OS" -Xlinker "$SDK_VERSION"

BIN_SRC=".build/release/upcoming"
if [ ! -x "$BIN_SRC" ]; then
  echo "ERROR: build did not produce $BIN_SRC" >&2
  exit 1
fi

echo "==> Running tests"
.build/release/UpcomingTests

APP_STAGING="build/Upcoming.app"
echo "==> Assembling $APP_STAGING"
rm -rf "$APP_STAGING"
mkdir -p "$APP_STAGING/Contents/MacOS" "$APP_STAGING/Contents/Resources"
cp "$BIN_SRC" "$APP_STAGING/Contents/MacOS/upcoming"
# SPM doesn't add @executable_path/../Frameworks to the rpath, which
# Sparkle.framework needs to be found at runtime.
install_name_tool -add_rpath @executable_path/../Frameworks \
  "$APP_STAGING/Contents/MacOS/upcoming" 2>/dev/null || true
cp Resources/Info.plist "$APP_STAGING/Contents/Info.plist"
printf "APPL????" > "$APP_STAGING/Contents/PkgInfo"
echo "==> Generating app icon"
# Compiled (not interpreted): the script shares CalendarGlyph.swift with
# the app target, and `swift` can't interpret multi-file programs.
swiftc -O Resources/make-icon.swift Sources/Upcoming/CalendarGlyph.swift -o build/make-icon
build/make-icon build/Upcoming.iconset
iconutil -c icns build/Upcoming.iconset -o "$APP_STAGING/Contents/Resources/Upcoming.icns"
# Reviewable preview of the icon, checked into the repo. Only rewrite it
# when the pixels changed: PNG encoding isn't byte-stable across
# toolchains, and a 7-byte re-encode dirtied the tree on every build.
NEW_ICON=build/Upcoming.iconset/icon_512x512.png
sips -s format bmp "$NEW_ICON" --out build/icon-new.bmp >/dev/null
sips -s format bmp docs/icon.png --out build/icon-old.bmp >/dev/null 2>&1 || true
if ! cmp -s build/icon-new.bmp build/icon-old.bmp; then
  cp "$NEW_ICON" docs/icon.png
fi

# SPM produces a resource bundle next to the binary when a target declares
# `resources:`. Copy it into the .app so Bundle.module resolves at runtime
# (it hard-crashes when the bundle is missing).
SPM_BUNDLE=".build/release/Upcoming_Upcoming.bundle"
if [ -d "$SPM_BUNDLE" ]; then
  cp -R "$SPM_BUNDLE" "$APP_STAGING/Contents/Resources/"
fi

# Sparkle framework (SPM binary artifact, inside an xcframework) for
# auto-updates.
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
  echo "==> Embedding Sparkle framework"
  mkdir -p "$APP_STAGING/Contents/Frameworks"
  cp -R "$SPARKLE_FW" "$APP_STAGING/Contents/Frameworks/"
fi

# WeatherKit (and any other managed entitlement) needs an embedded
# provisioning profile for Developer ID distribution. Drop the downloaded
# profile at Resources/embedded.provisionprofile and it gets bundled; the
# WeatherKit entitlement degrades gracefully (no temperature) without it.
PROFILE_SRC="Resources/embedded.provisionprofile"
if [ -f "$PROFILE_SRC" ]; then
  echo "==> Embedding provisioning profile"
  cp "$PROFILE_SRC" "$APP_STAGING/Contents/embedded.provisionprofile"
fi

echo "==> Signing with: $SIGN_ID"
if ! security find-identity -p codesigning -v | grep -qF "$SIGN_ID"; then
  echo "ERROR: signing identity not found in keychain: $SIGN_ID" >&2
  security find-identity -p codesigning -v >&2
  exit 1
fi
# Sign Sparkle's nested code first, with the Developer ID but WITHOUT the
# app's entitlements: propagating the managed WeatherKit/calendars
# entitlements onto Sparkle's helper bundles (their own bundle IDs aren't
# in the provisioning profile) makes them fail to launch. The app is signed
# separately below, without --deep, so it keeps these signatures intact.
if [ -d "$APP_STAGING/Contents/Frameworks/Sparkle.framework" ]; then
  echo "==> Signing Sparkle framework"
  codesign --force --deep --options runtime \
    --sign "$SIGN_ID" \
    "$APP_STAGING/Contents/Frameworks/Sparkle.framework"
fi

codesign --force --options runtime \
  --entitlements Resources/Upcoming.entitlements \
  --sign "$SIGN_ID" "$APP_STAGING"
codesign --verify --verbose --deep "$APP_STAGING" 2>&1 | head -5

APP_INSTALL="/Applications/Upcoming.app"
echo "==> Installing to $APP_INSTALL"
# Quit any running instance so the bundle can be replaced cleanly.
killall -q upcoming 2>/dev/null || true
sleep 0.2
rm -rf "$APP_INSTALL"
cp -R "$APP_STAGING" "$APP_INSTALL"

# Relaunch so the menu bar item comes back right after a rebuild.
echo "==> Relaunching"
open "$APP_INSTALL"

echo
echo "Done. Running in the menu bar (no Dock icon)."
echo "First launch prompts for Calendars access."
