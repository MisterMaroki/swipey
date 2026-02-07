#!/bin/bash
set -euo pipefail

APP_NAME="Swipey"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"

echo "Building ${APP_NAME}..."
swift build -c release

echo "Creating ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"

cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Swipey</string>
    <key>CFBundleIdentifier</key>
    <string>com.swipey.app</string>
    <key>CFBundleName</key>
    <string>Swipey</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signing ${APP_BUNDLE}..."
codesign --force --sign "Apple Development: Omar Maroki (85N386F5TF)" "${APP_BUNDLE}"

echo "Resetting accessibility permission (will need re-grant)..."
tccutil reset Accessibility com.swipey.app 2>/dev/null || true

echo "Done! ${APP_BUNDLE} created."
echo "To install: cp -r ${APP_BUNDLE} /Applications/"
echo "Then add /Applications/${APP_BUNDLE} to System Settings > Privacy & Security > Accessibility"
