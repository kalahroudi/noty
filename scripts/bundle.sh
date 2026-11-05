#!/bin/bash
# Builds Noty.app into ./dist (or $DIST_DIR). Usage: scripts/bundle.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP="${DIST_DIR:-dist}/Noty.app"
REPO="${APP_REPO:-kalahroudi/noty}"
BRANCH="${APP_BRANCH:-main}"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$COMMIT" != "unknown" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then COMMIT="$COMMIT-dirty"; fi

swift build -c release --product Noty
swift build -c release --product noty-mcp
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Noty" "$APP/Contents/MacOS/Noty"
cp "$BIN/noty-mcp" "$APP/Contents/MacOS/noty-mcp"

# App icon, drawn by the app itself so no image tools are needed.
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN/Noty" --write-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Noty</string>
  <key>CFBundleDisplayName</key><string>Noty</string>
  <key>CFBundleIdentifier</key><string>com.kalahroudi.noty</string>
  <key>CFBundleExecutable</key><string>Noty</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NotyCommit</key><string>$COMMIT</string>
  <key>NotyRepo</key><string>$REPO</string>
  <key>NotyBranch</key><string>$BRANCH</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSAppleEventsUsageDescription</key><string>Noty opens Terminal to run your agent (for example Claude Code) on the items you choose.</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Add to Noty</string></dict>
      <key>NSMessage</key><string>addToNoty</string>
      <key>NSPortName</key><string>Noty</string>
      <key>NSSendTypes</key><array><string>public.utf8-plain-text</string><string>public.png</string><string>public.tiff</string><string>com.apple.flat-rtfd</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Ad-hoc signed by default. With SIGN_IDENTITY set to a "Developer ID Application: ..." identity it is signed
# for distribution with the hardened runtime.
if [ "${SIGN_IDENTITY:--}" = "-" ]; then
  SIGN_FLAGS=(--force --sign -)
else
  SIGN_FLAGS=(--force --timestamp --options runtime --entitlements scripts/Noty.entitlements --sign "$SIGN_IDENTITY")
fi
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/noty-mcp"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
