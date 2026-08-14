#!/usr/bin/env bash
#
# Build a distributable drag-to-Applications DMG for Hosts Switchr.
#
# Usage:   ./scripts/make-dmg.sh
# Output:  dist/Hosts-Switchr-<version>.dmg   (version from App/project.yml MARKETING_VERSION)
# Needs:   xcodegen, create-dmg   (brew install xcodegen create-dmg)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/App"
BUILD_DIR="$APP_DIR/build/release"
DIST_DIR="$ROOT/dist"

command -v xcodegen   >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)"   >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "error: create-dmg not found (brew install create-dmg)" >&2; exit 1; }

VERSION="$(grep -m1 -E '^[[:space:]]*MARKETING_VERSION:' "$APP_DIR/project.yml" | sed -E 's/.*"([^"]+)".*/\1/')"
echo "==> Building Hosts Switchr $VERSION (Release)"

cd "$APP_DIR"
xcodegen
xcodebuild -project HostsSwitchr.xcodeproj -scheme HostsSwitchr \
  -configuration Release -derivedDataPath build/release \
  -destination 'platform=macOS' clean build

APP="$BUILD_DIR/Build/Products/Release/Hosts Switchr.app"
[ -d "$APP" ] || { echo "error: build did not produce $APP" >&2; exit 1; }

mkdir -p "$DIST_DIR"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"

# Updaters shipped before the 1.3.0 rename look for HostsSwitchr.app at the image root, so ship a
# second copy under the old name. Finder honours the hidden flag, so only one icon shows in the
# window; hdiutil carries the flag into the image. Droppable once nobody is running pre-1.3.0.
ditto "$STAGE/Hosts Switchr.app" "$STAGE/HostsSwitchr.app"
chflags hidden "$STAGE/HostsSwitchr.app"

DMG="$DIST_DIR/Hosts-Switchr-$VERSION.dmg"
rm -f "$DMG"

echo "==> Packaging $DMG"
create-dmg \
  --volname "Hosts Switchr" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Hosts Switchr.app" 150 190 \
  --hide-extension "Hosts Switchr.app" \
  --app-drop-link 450 190 \
  --no-internet-enable \
  "$DMG" "$STAGE"

echo "==> Done"
ls -lh "$DMG"
shasum -a 256 "$DMG"
