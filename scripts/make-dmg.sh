#!/usr/bin/env bash
#
# Build a Release Bytopolis.app and package it into a distributable .dmg.
#
#   Usage:  scripts/make-dmg.sh [version]
#
# If [version] is omitted it's read from the built app's CFBundleShortVersionString.
# Optional env for a signed build (otherwise it's ad-hoc "sign to run locally"):
#   CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="Bytopolis"
PROJECT="Bytopolis.xcodeproj"
CONFIG="Release"
DERIVED="$ROOT/build"
APP_NAME="Bytopolis.app"
DIST="$ROOT/dist"

echo "==> Building $SCHEME ($CONFIG)..."
XC_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -derivedDataPath "$DERIVED"
  -destination "generic/platform=macOS"
)
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  echo "    signing as: $CODE_SIGN_IDENTITY"
  XC_ARGS+=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY")
fi
xcodebuild "${XC_ARGS[@]}" clean build

APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME"
[[ -d "$APP" ]] || { echo "Build product not found at $APP"; exit 1; }

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null || echo 0.0.0)"
fi
VERSION="${VERSION#v}"   # tolerate a leading "v" from git tags
echo "==> Version: $VERSION"

# Stage the .app next to an /Applications symlink so users can drag-to-install.
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$DIST"
DMG="$DIST/Bytopolis-$VERSION.dmg"
rm -f "$DMG"

echo "==> Creating $DMG ..."
hdiutil create \
  -volname "Bytopolis $VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov "$DMG" >/dev/null
rm -rf "$STAGING"

echo "==> Done."
ls -lh "$DMG"
