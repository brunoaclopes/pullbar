#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Pullbar.app"
APP_EXECUTABLE="Pullbar"
BUNDLE_ID="com.pullbar.app"
BUILD_CONFIG="release"
BIN_PATH="$ROOT_DIR/.build/$BUILD_CONFIG/$APP_EXECUTABLE"
DEST_DIR="/Applications"
DEST_APP_PATH="$DEST_DIR/$APP_NAME"
STAGING_DIR="$(mktemp -d)"
STAGING_APP_PATH="$STAGING_DIR/$APP_NAME"
ICON_FILE_NAME="Pullbar.icns"
ICON_SOURCE_PATH="$ROOT_DIR/Assets/AppIcon/$ICON_FILE_NAME"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: ./scripts/install.sh [--run]

Builds Pullbar in release mode, bundles it as Pullbar.app,
installs it to /Applications, signs it ad-hoc, and optionally launches it.

Options:
  --run   Launch Pullbar after install
EOF
  exit 0
fi

RUN_AFTER_INSTALL=false
if [[ "${1:-}" == "--run" ]]; then
  RUN_AFTER_INSTALL=true
fi

echo "Building $APP_EXECUTABLE ($BUILD_CONFIG)..."
swift build -c "$BUILD_CONFIG" --package-path "$ROOT_DIR"

if [[ ! -f "$BIN_PATH" ]]; then
  echo "Binary not found at $BIN_PATH"
  exit 1
fi

echo "Creating app bundle..."
mkdir -p "$STAGING_APP_PATH/Contents/MacOS" "$STAGING_APP_PATH/Contents/Resources"
cp "$BIN_PATH" "$STAGING_APP_PATH/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$STAGING_APP_PATH/Contents/MacOS/$APP_EXECUTABLE"

ICON_PLIST_ENTRY=""
if [[ -f "$ICON_SOURCE_PATH" ]]; then
  cp "$ICON_SOURCE_PATH" "$STAGING_APP_PATH/Contents/Resources/$ICON_FILE_NAME"
  ICON_PLIST_ENTRY=$'  <key>CFBundleIconFile</key>\n  <string>Pullbar</string>'
  echo "Using app icon: $ICON_SOURCE_PATH"
else
  echo "No $ICON_FILE_NAME found at Assets/AppIcon. Using default app icon."
fi

cat > "$STAGING_APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Pullbar</string>
  <key>CFBundleDisplayName</key>
  <string>Pullbar</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE</string>
$ICON_PLIST_ENTRY
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

echo "Signing app bundle..."
codesign --force --deep --sign - --timestamp=none "$STAGING_APP_PATH"
codesign --verify --deep --strict --verbose "$STAGING_APP_PATH"

echo "Installing to $DEST_APP_PATH..."
pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true
rm -rf "$DEST_APP_PATH"
cp -R "$STAGING_APP_PATH" "$DEST_APP_PATH"

echo "Re-signing installed app bundle..."
codesign --force --deep --sign - --timestamp=none "$DEST_APP_PATH"
codesign --verify --deep --strict --verbose "$DEST_APP_PATH"

echo "Installed: $DEST_APP_PATH"

echo "Tip: Open Pullbar once from Applications, then enable 'Launch at login' in Settings."

if [[ "$RUN_AFTER_INSTALL" == true ]]; then
  echo "Launching Pullbar..."
  open "$DEST_APP_PATH"
fi
