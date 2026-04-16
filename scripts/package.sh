#!/usr/bin/env bash
set -euo pipefail

# Build VibeMove as a .app bundle and zip it for distribution.
# Usage: scripts/package.sh [VERSION]
#   VERSION defaults to 0.0.0-dev if not supplied.

VERSION="${1:-0.0.0-dev}"
APP_NAME="VibeMove"
BUNDLE_ID="ooo.fooo.vibemove"

# Move to repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

echo "==> swift build -c release"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
if [ ! -f "${BIN_PATH}" ]; then
    echo "ERROR: binary not found at ${BIN_PATH}" >&2
    exit 1
fi

DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
echo "==> packaging ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>VibeMove uses the camera to detect hand and body gestures and map them to keyboard input.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 fifteen42. MIT License.</string>
</dict>
</plist>
EOF

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "${APP_BUNDLE}"

ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"
rm -f "${ZIP_PATH}"
echo "==> zipping ${ZIP_PATH}"
(cd "${DIST_DIR}" && zip -r -q "$(basename "${ZIP_PATH}")" "${APP_NAME}.app")

echo
echo "Done."
echo "  bundle: ${APP_BUNDLE}"
echo "  zip:    ${ZIP_PATH}"
