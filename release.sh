#!/bin/bash
# Full release pipeline for Upcoming. Mirrors Uncommitted's release.sh
# (the donor pipeline); the Sparkle appcast section is in place but
# skips itself until the Sparkle dependency lands (auto-update work).
#
# Usage:
#   ./release.sh 0.2.0            # build, sign, notarize, GitHub release
#   ./release.sh 0.2.0 --dry-run  # build only, no notarization/upload
#
# Prerequisites:
#   - .env.local with UPCOMING_SIGN_IDENTITY and
#     UPCOMING_NOTARY_KEYCHAIN_PROFILE (see .env.example)
#   - `gh` CLI authenticated for thimo/upcoming
#
# Without .env.local the script falls back to ad-hoc signing — useful
# for testing the pipeline itself.
set -euo pipefail
cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>   e.g. $0 0.2.0" >&2
  exit 1
fi

DRY_RUN=false
for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && DRY_RUN=true
done

# ---------------------------------------------------------------------------
# Load signing credentials
# ---------------------------------------------------------------------------
SIGN_IDENTITY=""
NOTARY_PROFILE=""
if [ -f .env.local ]; then
  # shellcheck disable=SC1091
  set -a; source .env.local; set +a
  SIGN_IDENTITY="${UPCOMING_SIGN_IDENTITY:-}"
  NOTARY_PROFILE="${UPCOMING_NOTARY_KEYCHAIN_PROFILE:-}"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Signing identity: $SIGN_IDENTITY"
else
  echo "==> No UPCOMING_SIGN_IDENTITY — ad-hoc signing only."
fi

# ---------------------------------------------------------------------------
# Version bump in Info.plist
# ---------------------------------------------------------------------------
# CFBundleVersion = monotonically increasing build number from git
# (Sparkle compares this once auto-update lands).
BUILD_NUMBER=$(git rev-list --count HEAD)
echo "==> Version $VERSION (build $BUILD_NUMBER)"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"       Resources/Info.plist

# ---------------------------------------------------------------------------
# Build universal binary (separate arches + lipo)
# ---------------------------------------------------------------------------
echo "==> Building arm64"
swift build -c release --arch arm64

echo "==> Building x86_64"
swift build -c release --arch x86_64

echo "==> Running tests (arm64)"
.build/arm64-apple-macosx/release/UpcomingTests

echo "==> Creating universal binary"
mkdir -p build
lipo -create -output build/upcoming-universal \
  .build/arm64-apple-macosx/release/upcoming \
  .build/x86_64-apple-macosx/release/upcoming
lipo -info build/upcoming-universal

# ---------------------------------------------------------------------------
# Render icon (compiled: shares CalendarGlyph.swift with the app target)
# ---------------------------------------------------------------------------
echo "==> Rendering icon"
swiftc -O Resources/make-icon.swift Sources/Upcoming/CalendarGlyph.swift -o build/make-icon
build/make-icon build/Upcoming.iconset >/dev/null
iconutil -c icns build/Upcoming.iconset -o build/Upcoming.icns

# ---------------------------------------------------------------------------
# Assemble .app bundle
# ---------------------------------------------------------------------------
APP="build/Upcoming.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/upcoming-universal "$APP/Contents/MacOS/upcoming"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/Upcoming.icns "$APP/Contents/Resources/Upcoming.icns"
printf "APPL????" > "$APP/Contents/PkgInfo"

# SPM resource bundle (arm64 build — identical across arches).
SPM_BUNDLE=".build/arm64-apple-macosx/release/Upcoming_Upcoming.bundle"
if [ -d "$SPM_BUNDLE" ]; then
  cp -R "$SPM_BUNDLE" "$APP/Contents/Resources/"
fi

# ---------------------------------------------------------------------------
# Code signing
# ---------------------------------------------------------------------------
if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Signing with Developer ID (hardened runtime + timestamp)"
  codesign --force \
    --sign "$SIGN_IDENTITY" \
    --entitlements Resources/Upcoming.entitlements \
    --options runtime \
    --timestamp \
    "$APP"
else
  echo "==> Ad-hoc signing"
  codesign --force --sign - "$APP"
fi
codesign --verify --verbose "$APP" 2>&1 | head -5

# ---------------------------------------------------------------------------
# Zip for distribution (ditto preserves code sig + extended attrs)
# ---------------------------------------------------------------------------
ZIP_NAME="Upcoming-${VERSION}.zip"
ZIP_PATH="build/$ZIP_NAME"
echo "==> Creating $ZIP_PATH"
rm -f "$ZIP_PATH"
(cd build && ditto -c -k --keepParent Upcoming.app "$ZIP_NAME")

# ---------------------------------------------------------------------------
# Notarize + staple (gated)
# ---------------------------------------------------------------------------
if [ -n "$SIGN_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ] && [ "$DRY_RUN" = false ]; then
  echo "==> Submitting to notarytool…"
  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo "==> Stapling ticket"
  xcrun stapler staple "$APP"

  # Re-zip with the stapled ticket included.
  echo "==> Re-zipping with stapled ticket"
  rm -f "$ZIP_PATH"
  (cd build && ditto -c -k --keepParent Upcoming.app "$ZIP_NAME")

  echo "==> Gatekeeper check"
  spctl --assess --type execute --verbose "$APP" 2>&1 || true
else
  echo "   Skipping notarization (no identity/profile or --dry-run)."
fi

# ---------------------------------------------------------------------------
# Sparkle appcast (no-op until the Sparkle dependency lands)
# ---------------------------------------------------------------------------
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
if [ -x "$SPARKLE_BIN/generate_appcast" ] && [ "$DRY_RUN" = false ]; then
  echo "==> Generating appcast.xml"
  "$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/thimo/upcoming/releases/download/v${VERSION}/" \
    --link "https://github.com/thimo/upcoming/releases/tag/v${VERSION}" \
    --maximum-deltas 0 \
    build/
  if [ -f build/appcast.xml ]; then
    # generate_appcast applies --download-url-prefix to every item,
    # including historical zips in build/ — rewrite so each item's tag
    # matches the version in its filename (Uncommitted's lesson).
    sed -E -i '' 's|/releases/download/v[^/]+/Upcoming-([^"]+)\.zip|/releases/download/v\1/Upcoming-\1.zip|g' build/appcast.xml
    cp build/appcast.xml appcast.xml
    echo "   appcast.xml updated in repo root."
  fi
else
  echo "   Skipping appcast — generate_appcast not found or --dry-run."
fi

# ---------------------------------------------------------------------------
# GitHub release
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = true ]; then
  echo
  echo "Done (dry run). Artifact: $ZIP_PATH"
  exit 0
fi

if command -v gh &>/dev/null; then
  TAG="v${VERSION}"
  echo "==> Creating GitHub release $TAG"

  # CHANGELOG.md entry as release body when present; otherwise
  # auto-generated notes.
  NOTES_FILE=""
  if [ -f CHANGELOG.md ]; then
    NOTES_FILE=$(mktemp -t "upcoming-${VERSION}-notes.XXXXXX.md")
    awk -v v="${VERSION}" '
      $0 ~ "^## v" v "( |$)" { found = 1; next }
      found && /^## v/ { exit }
      found { print }
    ' CHANGELOG.md > "$NOTES_FILE"
    if [ ! -s "$NOTES_FILE" ]; then
      rm -f "$NOTES_FILE"
      NOTES_FILE=""
    fi
  fi

  if git rev-parse "$TAG" &>/dev/null; then
    echo "   Tag exists — uploading to existing release."
    gh release upload "$TAG" "$ZIP_PATH" --clobber
    if [ -n "$NOTES_FILE" ]; then
      gh release edit "$TAG" --notes-file "$NOTES_FILE"
    fi
  elif [ -n "$NOTES_FILE" ]; then
    gh release create "$TAG" "$ZIP_PATH" \
      --title "Upcoming ${VERSION}" \
      --notes-file "$NOTES_FILE"
  else
    gh release create "$TAG" "$ZIP_PATH" \
      --title "Upcoming ${VERSION}" \
      --generate-notes
  fi
  [ -n "$NOTES_FILE" ] && rm -f "$NOTES_FILE"
  echo "   https://github.com/thimo/upcoming/releases/tag/$TAG"
else
  echo "   gh CLI not found — upload $ZIP_PATH manually."
fi

# ---------------------------------------------------------------------------
# Commit version bump + appcast (local only — pushing stays manual)
# ---------------------------------------------------------------------------
if ! git diff --quiet Resources/Info.plist appcast.xml 2>/dev/null; then
  git add Resources/Info.plist
  [ -f appcast.xml ] && git add appcast.xml
  git commit -m "Release v${VERSION}"
  echo "==> Committed. Push to main when ready."
fi

echo
echo "Done. Upcoming ${VERSION} at $ZIP_PATH"
